import boto3
import json
import os
from datetime import datetime, timedelta

ecs = boto3.client('ecs')
cloudwatch = boto3.client('cloudwatch')
sqs = boto3.client('sqs')
sns = boto3.client('sns')

CLUSTER = os.environ['CLUSTER_NAME']
SERVICE = os.environ['SERVICE_NAME']
QUEUE_URL = os.environ['QUEUE_URL']
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']
CPU_HIGH_THRESHOLD = float(os.environ['CPU_HIGH_THRESHOLD'])
CPU_LOW_THRESHOLD = float(os.environ['CPU_LOW_THRESHOLD'])
QUEUE_DEPTH_THRESHOLD = float(os.environ['QUEUE_DEPTH_THRESHOLD'])
TICK_RATE_REDUCTION = float(os.environ['TICK_RATE_REDUCTION'])

def lambda_handler(event, context):
    """
    Health Monitor Lambda - Evaluates system health and triggers recovery
    """
    print(f"🧠 Health Monitor Start - {datetime.now().isoformat()}")
    
    try:
        # Collect metrics
        metrics = collect_metrics()
        
        # Evaluate health
        health_status = evaluate_health(metrics)
        
        # Take recovery actions if needed
        recovery_actions = determine_recovery_actions(health_status, metrics)
        
        if recovery_actions:
            execute_recovery(recovery_actions, metrics)
        
        # Log health status
        log_health_status(health_status, metrics, recovery_actions)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'status': 'ok' if not recovery_actions else 'recovery_triggered',
                'metrics': metrics,
                'health': health_status,
                'actions': recovery_actions
            })
        }
        
    except Exception as e:
        print(f"❌ Error in health monitor: {str(e)}")
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject="🚨 Health Monitor Error",
            Message=f"Health monitor failed: {str(e)}"
        )
        raise

def collect_metrics():
    """
    Collect key metrics from CloudWatch and SQS
    """
    now = datetime.utcnow()
    five_min_ago = now - timedelta(minutes=5)
    
    # Get CPU metrics
    cpu_response = cloudwatch.get_metric_statistics(
        Namespace='AWS/ECS',
        MetricName='CPUUtilization',
        Dimensions=[
            {'Name': 'ClusterName', 'Value': CLUSTER},
            {'Name': 'ServiceName', 'Value': SERVICE}
        ],
        StartTime=five_min_ago,
        EndTime=now,
        Period=60,
        Statistics=['Average', 'Maximum']
    )
    
    # Get Memory metrics
    memory_response = cloudwatch.get_metric_statistics(
        Namespace='AWS/ECS',
        MetricName='MemoryUtilization',
        Dimensions=[
            {'Name': 'ClusterName', 'Value': CLUSTER},
            {'Name': 'ServiceName', 'Value': SERVICE}
        ],
        StartTime=five_min_ago,
        EndTime=now,
        Period=60,
        Statistics=['Average', 'Maximum']
    )
    
    # Get SQS Queue Depth
    queue_attrs = sqs.get_queue_attributes(
        QueueUrl=QUEUE_URL,
        AttributeNames=['ApproximateNumberOfMessages', 'ApproximateNumberOfNotVisibleMessages']
    )
    
    # Get ECS Service state
    service_response = ecs.describe_services(
        cluster=CLUSTER,
        services=[SERVICE]
    )
    
    service_info = service_response['services'][0]
    
    cpu_avg = cpu_response['Datapoints'][0]['Average'] if cpu_response['Datapoints'] else 0
    cpu_max = cpu_response['Datapoints'][0]['Maximum'] if cpu_response['Datapoints'] else 0
    memory_avg = memory_response['Datapoints'][0]['Average'] if memory_response['Datapoints'] else 0
    memory_max = memory_response['Datapoints'][0]['Maximum'] if memory_response['Datapoints'] else 0
    queue_depth = int(queue_attrs['Attributes'].get('ApproximateNumberOfMessages', 0))
    queue_invisible = int(queue_attrs['Attributes'].get('ApproximateNumberOfNotVisibleMessages', 0))
    
    return {
        'timestamp': now.isoformat(),
        'cpu': {
            'average': round(cpu_avg, 2),
            'maximum': round(cpu_max, 2)
        },
        'memory': {
            'average': round(memory_avg, 2),
            'maximum': round(memory_max, 2)
        },
        'queue': {
            'depth': queue_depth,
            'in_flight': queue_invisible,
            'total': queue_depth + queue_invisible
        },
        'tasks': {
            'running': service_info['runningCount'],
            'desired': service_info['desiredCount'],
            'pending': service_info['pendingCount']
        },
        'deployment': {
            'status': service_info['deployments'][0]['status'] if service_info['deployments'] else 'UNKNOWN'
        }
    }

def evaluate_health(metrics):
    """
    Evaluate system health based on metrics
    """
    health = {
        'overall': 'healthy',
        'issues': []
    }
    
    # Check CPU
    if metrics['cpu']['maximum'] > CPU_HIGH_THRESHOLD:
        health['overall'] = 'degraded'
        health['issues'].append(f"⚠️ High CPU: {metrics['cpu']['maximum']}%")
    
    # Check Memory
    if metrics['memory']['maximum'] > 85:
        health['overall'] = 'degraded'
        health['issues'].append(f"⚠️ High Memory: {metrics['memory']['maximum']}%")
    
    # Check Queue Depth
    if metrics['queue']['depth'] > QUEUE_DEPTH_THRESHOLD:
        health['overall'] = 'degraded'
        health['issues'].append(f"⚠️ Queue Backlog: {metrics['queue']['depth']} messages")
    
    # Check Task Count
    if metrics['tasks']['running'] < metrics['tasks']['desired']:
        health['overall'] = 'degraded'
        health['issues'].append(f"⚠️ Task Count Low: {metrics['tasks']['running']}/{metrics['tasks']['desired']}")
    
    # Check Deployment Status
    if metrics['deployment']['status'] not in ['ACTIVE', 'PRIMARY']:
        health['overall'] = 'degraded'
        health['issues'].append(f"⚠️ Deployment Status: {metrics['deployment']['status']}")
    
    return health

def determine_recovery_actions(health_status, metrics):
    """
    Determine what recovery actions should be taken
    """
    actions = []
    
    if health_status['overall'] == 'healthy':
        return actions
    
    # High CPU Recovery
    if metrics['cpu']['maximum'] > CPU_HIGH_THRESHOLD:
        actions.append({
            'type': 'restart_ecs',
            'reason': f"High CPU: {metrics['cpu']['maximum']}%",
            'priority': 'high'
        })
    
    # Queue Backlog Recovery
    if metrics['queue']['depth'] > QUEUE_DEPTH_THRESHOLD:
        actions.append({
            'type': 'scale_up',
            'reason': f"Queue backlog: {metrics['queue']['depth']} messages",
            'priority': 'high'
        })
        actions.append({
            'type': 'reduce_simulation_pressure',
            'reason': f"Backpressure control",
            'reduction_factor': TICK_RATE_REDUCTION,
            'priority': 'high'
        })
    
    # Low Task Count Recovery
    if metrics['tasks']['running'] < metrics['tasks']['desired']:
        actions.append({
            'type': 'restart_tasks',
            'reason': f"Low task count: {metrics['tasks']['running']}/{metrics['tasks']['desired']}",
            'priority': 'critical'
        })
    
    return actions

def execute_recovery(actions, metrics):
    """
    Execute recovery actions
    """
    print(f"🔧 Executing {len(actions)} recovery actions")
    
    for action in actions:
        try:
            if action['type'] == 'restart_ecs':
                print(f"🔁 Restarting ECS tasks...")
                ecs.update_service(
                    cluster=CLUSTER,
                    service=SERVICE,
                    forceNewDeployment=True
                )
            
            elif action['type'] == 'scale_up':
                print(f"📈 Scaling up ECS tasks...")
                # Scale up is handled by AppAutoScaling, but we can trigger SNS for urgent scaling
                sns.publish(
                    TopicArn=SNS_TOPIC_ARN,
                    Subject="📈 Scale-Up Triggered",
                    Message=json.dumps(action)
                )
            
            elif action['type'] == 'reduce_simulation_pressure':
                print(f"🧯 Reducing simulation pressure...")
                # Send backpressure signal to simulation
                sns.publish(
                    TopicArn=SNS_TOPIC_ARN,
                    Subject="🧯 Simulation Backpressure",
                    Message=json.dumps({
                        'action': 'reduce_tick_rate',
                        'factor': action['reduction_factor'],
                        'reason': action['reason'],
                        'queue_depth': metrics['queue']['depth']
                    })
                )
            
            elif action['type'] == 'restart_tasks':
                print(f"🔁 Force restarting all tasks...")
                ecs.update_service(
                    cluster=CLUSTER,
                    service=SERVICE,
                    forceNewDeployment=True
                )
            
            print(f"✅ Action completed: {action['type']}")
        
        except Exception as e:
            print(f"❌ Error executing action {action['type']}: {str(e)}")

def log_health_status(health_status, metrics, actions):
    """
    Log health status to CloudWatch custom metric
    """
    cloudwatch.put_metric_data(
        Namespace='AICiv/Health',
        MetricData=[
            {
                'MetricName': 'SystemHealth',
                'Value': 1 if health_status['overall'] == 'healthy' else 0,
                'Unit': 'None',
                'Timestamp': datetime.utcnow()
            },
            {
                'MetricName': 'RecoveryActionsTriggered',
                'Value': len(actions),
                'Unit': 'Count',
                'Timestamp': datetime.utcnow()
            }
        ]
    )
    
    print(f"📊 Health Status: {health_status['overall']}")
    print(f"📊 Issues: {len(health_status['issues'])}")
    print(f"📊 Recovery Actions: {len(actions)}")
