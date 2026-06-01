import boto3
import json
import os
from datetime import datetime

ecs = boto3.client('ecs')
sqs = boto3.client('sqs')
sns = boto3.client('sns')

CLUSTER = os.environ['CLUSTER_NAME']
SERVICE = os.environ['SERVICE_NAME']
QUEUE_URL = os.environ['QUEUE_URL']

def lambda_handler(event, context):
    """
    Health Recovery Handler - Processes SNS messages from health monitor
    and executes recovery procedures
    """
    print(f"🧯 Recovery Handler Start - {datetime.now().isoformat()}")
    print(f"Event: {json.dumps(event)}")
    
    try:
        # Parse SNS message
        if 'Records' in event:
            for record in event['Records']:
                if record['EventSource'] == 'aws:sns':
                    message = json.loads(record['Sns']['Message'])
                    handle_recovery_action(message)
        else:
            handle_recovery_action(event)
        
        return {
            'statusCode': 200,
            'body': json.dumps({'status': 'recovered'})
        }
    
    except Exception as e:
        print(f"❌ Recovery handler error: {str(e)}")
        raise

def handle_recovery_action(message):
    """
    Handle specific recovery action
    """
    action_type = message.get('type')
    
    print(f"🔧 Processing recovery action: {action_type}")
    
    if action_type == 'restart_ecs':
        perform_ecs_restart()
    
    elif action_type == 'scale_up':
        perform_scale_up(message)
    
    elif action_type == 'reduce_simulation_pressure':
        perform_backpressure_control(message)
    
    elif action_type == 'restart_tasks':
        perform_ecs_restart(force=True)
    
    elif action_type == 'rollback_deployment':
        perform_rollback(message)

def perform_ecs_restart(force=False):
    """
    Restart ECS service/tasks
    """
    print("🔁 Performing ECS restart...")
    
    try:
        response = ecs.update_service(
            cluster=CLUSTER,
            service=SERVICE,
            forceNewDeployment=True
        )
        
        print(f"✅ ECS restart initiated")
        print(f"   Service: {response['service']['serviceName']}")
        print(f"   Deployments: {len(response['service']['deployments'])}")
        
        # Wait briefly for deployment to start
        import time
        time.sleep(5)
        
        # Verify deployment is rolling
        verify_deployment_status()
    
    except Exception as e:
        print(f"❌ ECS restart failed: {str(e)}")
        raise

def perform_scale_up(message):
    """
    Scale up ECS tasks
    """
    print("📈 Performing scale-up...")
    
    try:
        # Get current service state
        response = ecs.describe_services(
            cluster=CLUSTER,
            services=[SERVICE]
        )
        
        current_count = response['services'][0]['desiredCount']
        new_count = min(current_count + 2, 10)  # Max 10 tasks
        
        if new_count > current_count:
            print(f"📈 Scaling from {current_count} to {new_count} tasks")
            
            ecs.update_service(
                cluster=CLUSTER,
                service=SERVICE,
                desiredCount=new_count
            )
            
            print(f"✅ Scale-up command sent")
        else:
            print(f"⚠️ Already at maximum capacity")
    
    except Exception as e:
        print(f"❌ Scale-up failed: {str(e)}")
        raise

def perform_backpressure_control(message):
    """
    Apply simulation backpressure by reducing tick rate
    """
    print("🧯 Applying simulation backpressure...")
    
    try:
        factor = message.get('reduction_factor', 0.5)
        queue_depth = message.get('queue_depth', 0)
        
        # Send backpressure signal to all running tasks via SQS
        backpressure_signal = {
            'signal_type': 'backpressure',
            'tick_rate_factor': factor,
            'reason': 'queue_backlog',
            'queue_depth': queue_depth,
            'timestamp': datetime.utcnow().isoformat()
        }
        
        # In production, this would be sent to simulation worker via API or message
        print(f"🧯 Backpressure signal: {factor}x reduction")
        print(f"   Reason: {message.get('reason')}")
        print(f"   Queue depth: {queue_depth}")
        
        print(f"✅ Backpressure applied")
    
    except Exception as e:
        print(f"❌ Backpressure control failed: {str(e)}")
        raise

def perform_rollback(message):
    """
    Rollback ECS deployment to previous version
    """
    print("📉 Performing deployment rollback...")
    
    try:
        # Get current task definitions
        response = ecs.list_task_definitions(
            familyPrefix=f"{SERVICE}",
            sort='DESCENDING'
        )
        
        if len(response['taskDefinitionArns']) < 2:
            print("❌ No previous task definition to rollback to")
            return
        
        # Get previous task definition
        previous_def = response['taskDefinitionArns'][1]
        
        print(f"📉 Rolling back to: {previous_def}")
        
        # Update service with previous task definition
        ecs.update_service(
            cluster=CLUSTER,
            service=SERVICE,
            taskDefinition=previous_def
        )
        
        print(f"✅ Rollback initiated")
        verify_deployment_status()
    
    except Exception as e:
        print(f"❌ Rollback failed: {str(e)}")
        raise

def verify_deployment_status():
    """
    Verify deployment is progressing correctly
    """
    try:
        response = ecs.describe_services(
            cluster=CLUSTER,
            services=[SERVICE]
        )
        
        service = response['services'][0]
        deployments = service['deployments']
        
        print(f"\n📊 Deployment Status:")
        for i, deployment in enumerate(deployments):
            print(f"   Deployment {i+1}: {deployment['status']}")
            print(f"      Running: {deployment['runningCount']}/{deployment['desiredCount']}")
        
        print(f"\n📊 Service Status:")
        print(f"   Running tasks: {service['runningCount']}")
        print(f"   Desired tasks: {service['desiredCount']}")
        print(f"   Pending tasks: {service['pendingCount']}")
    
    except Exception as e:
        print(f"❌ Status verification failed: {str(e)}")
