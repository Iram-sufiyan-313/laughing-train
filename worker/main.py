#!/usr/bin/env python3
"""
AI Civilization Simulation Worker
Self-healing autonomous runtime
"""

import os
import sys
import json
import time
import logging
from datetime import datetime
import boto3
from flask import Flask, jsonify

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# AWS Clients
sqs = boto3.client('sqs')
cloudwatch = boto3.client('cloudwatch')

# Configuration from environment
QUEUE_URL = os.environ.get('QUEUE_URL')
QUEUE_MAX_DEPTH = int(os.environ.get('QUEUE_MAX_DEPTH', 5000))
TICK_RATE_BASE = int(os.environ.get('TICK_RATE_BASE', 100))
TICK_RATE_FACTOR = 1.0  # Dynamic factor from health monitor

# Flask app
app = Flask(__name__)

class SimulationWorker:
    def __init__(self):
        self.running = True
        self.messages_processed = 0
        self.errors = 0
        self.tick_rate_factor = 1.0
        logger.info("🧬 Simulation Worker Initialized")
    
    def process_messages(self):
        """Main processing loop"""
        logger.info("🔄 Starting message processing loop")
        
        while self.running:
            try:
                # Check queue depth for backpressure
                queue_depth = self.get_queue_depth()
                
                # Apply backpressure if queue is deep
                if queue_depth > QUEUE_MAX_DEPTH * 0.8:
                    logger.warning(f"⚠️ Queue backpressure: {queue_depth} messages")
                    self.apply_backpressure(queue_depth)
                
                # Receive messages
                response = sqs.receive_message(
                    QueueUrl=QUEUE_URL,
                    MaxNumberOfMessages=10,
                    WaitTimeSeconds=20,
                    AttributeNames=['All']
                )
                
                messages = response.get('Messages', [])
                
                if not messages:
                    logger.debug("No messages, waiting...")
                    time.sleep(1)
                    continue
                
                # Process each message
                for message in messages:
                    try:
                        self.process_message(message)
                        self.messages_processed += 1
                    except Exception as e:
                        logger.error(f"❌ Error processing message: {str(e)}")
                        self.errors += 1
                
                # Calculate dynamic tick rate
                tick_delay = 1.0 / (TICK_RATE_BASE * self.tick_rate_factor)
                time.sleep(tick_delay)
            
            except KeyboardInterrupt:
                logger.info("⛔ Shutdown signal received")
                self.running = False
            except Exception as e:
                logger.error(f"🔥 Worker error: {str(e)}")
                self.errors += 1
                time.sleep(5)  # Backoff on error
    
    def process_message(self, message):
        """Process a single SQS message"""
        try:
            body = json.loads(message['Body'])
            
            # Simulate work
            logger.info(f"🧠 Processing simulation tick: {body.get('tick_id')}")
            
            # Actual simulation logic would go here
            time.sleep(0.1)  # Simulate work
            
            # Delete message from queue
            sqs.delete_message(
                QueueUrl=QUEUE_URL,
                ReceiptHandle=message['ReceiptHandle']
            )
            
            logger.debug(f"✅ Message processed")
        
        except Exception as e:
            logger.error(f"Error processing message: {str(e)}")
            raise
    
    def get_queue_depth(self):
        """Get current queue depth"""
        try:
            attrs = sqs.get_queue_attributes(
                QueueUrl=QUEUE_URL,
                AttributeNames=['ApproximateNumberOfMessages']
            )
            return int(attrs['Attributes'].get('ApproximateNumberOfMessages', 0))
        except Exception as e:
            logger.warning(f"Failed to get queue depth: {str(e)}")
            return 0
    
    def apply_backpressure(self, queue_depth):
        """Apply backpressure by reducing tick rate"""
        # Calculate reduction factor
        factor = max(0.1, 1.0 - (queue_depth / QUEUE_MAX_DEPTH))
        self.tick_rate_factor = factor
        
        logger.warning(f"🧯 Backpressure applied: {factor:.2f}x tick rate")
        
        # Report to CloudWatch
        try:
            cloudwatch.put_metric_data(
                Namespace='AICiv/Worker',
                MetricData=[
                    {
                        'MetricName': 'TickRateFactor',
                        'Value': factor,
                        'Unit': 'None'
                    },
                    {
                        'MetricName': 'QueueDepth',
                        'Value': queue_depth,
                        'Unit': 'Count'
                    }
                ]
            )
        except Exception as e:
            logger.warning(f"Failed to report metrics: {str(e)}")
    
    def get_stats(self):
        """Get worker statistics"""
        return {
            'messages_processed': self.messages_processed,
            'errors': self.errors,
            'tick_rate_factor': self.tick_rate_factor,
            'uptime': time.time()
        }

# Global worker instance
worker = SimulationWorker()

# Flask routes
@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'ok',
        'timestamp': datetime.utcnow().isoformat(),
        'worker': 'running'
    }), 200

@app.route('/state', methods=['GET'])
def state():
    """Get current state"""
    return jsonify({
        'status': 'running',
        'stats': worker.get_stats(),
        'tick_rate_factor': worker.tick_rate_factor,
        'timestamp': datetime.utcnow().isoformat()
    }), 200

@app.route('/metrics', methods=['GET'])
def metrics():
    """Get metrics"""
    stats = worker.get_stats()
    return jsonify({
        'messages_processed': stats['messages_processed'],
        'errors': stats['errors'],
        'error_rate': stats['errors'] / max(stats['messages_processed'], 1),
        'tick_rate_factor': stats['tick_rate_factor']
    }), 200

if __name__ == '__main__':
    import threading
    
    logger.info("🚀 AI Civilization Worker Starting")
    
    # Start message processing in background thread
    processor_thread = threading.Thread(
        target=worker.process_messages,
        daemon=True
    )
    processor_thread.start()
    
    # Start Flask server
    logger.info("🌐 Starting Flask server on 0.0.0.0:8000")
    app.run(
        host='0.0.0.0',
        port=8000,
        debug=False,
        use_reloader=False
    )
