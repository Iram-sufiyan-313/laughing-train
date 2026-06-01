# 🚀 Automated Deployment Instructions

## Quick Start (3 Steps)

### Step 1: Add AWS Credentials to GitHub Secrets

1. Go to: `https://github.com/Iram-sufiyan-313/laughing-train/settings/secrets/actions`

2. Click **New repository secret** and add:

   **Secret 1:**
   - Name: `AWS_ACCESS_KEY_ID`
   - Value: Your AWS access key ID

   **Secret 2:**
   - Name: `AWS_SECRET_ACCESS_KEY`
   - Value: Your AWS secret access key

### Step 2: Create AWS IAM User (if needed)

```bash
# Create IAM user
aws iam create-user --user-name github-actions-deploy

# Attach admin policy (or use custom restricted policy)
aws iam attach-user-policy \
  --user-name github-actions-deploy \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Create access keys
aws iam create-access-key --user-name github-actions-deploy
```

Copy the `AccessKeyId` and `SecretAccessKey` to GitHub Secrets.

### Step 3: Trigger Deployment

**Option A: Push to main branch**
```bash
git add .
git commit -m "Deploy infrastructure"
git push origin main
```

**Option B: Manual trigger**
1. Go to **Actions** tab
2. Select **🚀 Deploy Infrastructure & Container** workflow
3. Click **Run workflow**

---

## 🎯 What Happens Automatically

### Phase 1: Infrastructure Deployment (2-3 min)
- ✅ Terraform init/plan/apply
- ✅ Creates VPC, ECS cluster, SQS queues
- ✅ Deploys Lambda functions
- ✅ Sets up CloudWatch alarms
- ✅ Configures auto-scaling

### Phase 2: Container Build & Push (3-5 min)
- ✅ Builds Docker image
- ✅ Tags with commit SHA + latest
- ✅ Pushes to ECR

### Phase 3: ECS Deployment (2-3 min)
- ✅ Forces new ECS deployment
- ✅ Waits for service stability
- ✅ Verifies all tasks running

### Phase 4: Smoke Tests (1-2 min)
- ✅ Health checks
- ✅ Metric validation
- ✅ Service status verification

**Total time: ~8-13 minutes**

---

## 📊 Monitoring Deployment

### Watch Workflow Progress
1. Go to: **Actions** tab
2. Click on the running workflow
3. Watch each job execute

### View Live Logs
```bash
# After deployment completes
aws logs tail /ecs/ai-civ-worker --follow
aws logs tail /aws/lambda/ai-civ-health-monitor --follow
```

### Check Infrastructure
```bash
# List ECS clusters
aws ecs list-clusters

# Describe service
aws ecs describe-services \
  --cluster ai-civ-cluster \
  --services ai-civ-worker

# View ECR images
aws ecr describe-images --repository-name ai-civ-worker
```

---

## ✅ Verify Deployment

### Check if running
```bash
# Get service status
aws ecs describe-services \
  --cluster ai-civ-cluster \
  --services ai-civ-worker \
  --query 'services[0].[runningCount, desiredCount]'

# Should output: [2, 2] (2 tasks running)
```

### Check logs
```bash
# ECS logs
aws logs tail /ecs/ai-civ-worker --follow

# Health monitor logs
aws logs tail /aws/lambda/ai-civ-health-monitor --follow
```

### Test endpoints
```bash
# Get task IP (if public)
aws ecs list-tasks --cluster ai-civ-cluster

aws ecs describe-tasks \
  --cluster ai-civ-cluster \
  --tasks <task-arn> \
  --query 'tasks[0].containerInstanceArn'

# Curl health endpoint (from within VPC or bastion)
curl http://<task-ip>:8000/health
```

---

## 🔧 Troubleshooting

### Workflow fails: "AWS credentials not found"
**Fix**: Add secrets to GitHub (see Step 1)

### Workflow fails: "Access Denied"
**Fix**: Ensure IAM user has `AdministratorAccess` or required permissions

### ECS tasks won't start
**Check logs:**
```bash
aws logs tail /ecs/ai-civ-worker --follow
```

**Common causes:**
- Docker image not in ECR
- Insufficient task memory/CPU
- Security group blocking traffic

### ECR image push fails
**Fix**: Ensure Docker is installed and running
```bash
docker --version
docker ps
```

### Terraform state issues
**Fix**: Delete backend bucket and retry
```bash
aws s3 rm s3://ai-civ-terraform-state --recursive
```

---

## 📝 Optional: Customize Deployment

### Change AWS Region
Edit `.github/workflows/infrastructure-deploy.yml`:
```yaml
env:
  AWS_REGION: us-west-2  # Change here
```

### Change Task Count
Edit `infra/variables.tf`:
```hcl
# Initial desired count
desired_count = 5  # Instead of 2
```

### Add Slack Notifications
Add to GitHub Secrets:
- `SLACK_WEBHOOK_URL`: Your Slack incoming webhook

Then GitHub will notify Slack on deployment completion.

---

## 🚀 Full Deployment Checklist

- [ ] AWS IAM user created with access keys
- [ ] GitHub Secrets added (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
- [ ] Repository code pushed to main branch
- [ ] GitHub Actions workflow triggered (automatically or manually)
- [ ] Workflow completes successfully (8-13 min)
- [ ] ECS service running 2 tasks
- [ ] CloudWatch dashboard shows metrics
- [ ] Lambda functions executing (check logs)
- [ ] SQS queues created
- [ ] Health monitor running (every 5 min)

---

## 📞 Support

**Stuck?** Check:
1. Workflow logs in GitHub Actions tab
2. CloudWatch logs for ECS/Lambda
3. AWS Console → ECS Clusters
4. AWS Console → CloudWatch Alarms

---

**Your system is now fully automated. Push code → Deploy automatically! 🚀**
