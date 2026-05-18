# 🚀 Creative Studio - Beginner's Deployment Guide

Welcome! This guide is designed to help you deploy the **Creative Studio** platform on Google Cloud. You don't need to be an expert in cloud infrastructure to follow this—just take it one step at a time, copy the commands exactly as written, and you'll have the platform running in no time!

---

## Step 1: Get Your Tools Ready
Before we start, you need a few basic tools installed on your computer:
1. **Google Cloud CLI (`gcloud`)**: To talk to Google Cloud. [Install here](https://cloud.google.com/sdk/docs/install)
2. **Terraform (v1.6+)**: To automatically create the servers and databases. [Install here](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
3. **Helm (v3.13+)**: To install our application code onto the servers. [Install here](https://helm.sh/docs/intro/install/)
4. **Kubectl**: To interact with our Kubernetes cluster. You can install this by running: `gcloud components install kubectl`

---

## Step 2: Log In to Google Cloud
First, we need to log in to your Google Cloud account so the tools have permission to create resources.

Open your terminal and run:
```bash
# Set these to your specific Google Cloud project and region
export PROJECT_ID="ravi-argolis-01"
export REGION="asia-south1"

# Log into Google Cloud (this will open a browser window)
gcloud auth login --update-adc

# Tell gcloud to use your project
gcloud config set project "$PROJECT_ID"
```

---

## Step 3: Enable APIs and Create a State Bucket
Google Cloud needs certain APIs turned on. Terraform also needs a "State Bucket" to keep track of what it creates.

**1. Create the State Bucket:**
```bash
export STATE_BUCKET="${PROJECT_ID}-tfstate"

gcloud storage buckets create "gs://${STATE_BUCKET}" \
  --project="$PROJECT_ID" \
  --location="$REGION" \
  --uniform-bucket-level-access \
  --public-access-prevention

gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning
```

**2. Enable Required APIs:**
```bash
gcloud services enable \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  secretmanager.googleapis.com \
  --project="$PROJECT_ID"
```

---

## Step 4: Create Passwords and Certificates (Secrets)
The application needs a secure database password and SSL certificates (for HTTPS). We will store these securely in Google Secret Manager.

**1. Create a random Database Password:**
```bash
echo -n "$(openssl rand -base64 24)" | \
  gcloud secrets create creative-studio-db-password-dev \
    --replication-policy=automatic --data-file=-
```

**2. Upload your SSL Certificates:**
*(Note: Ensure you have `tls.crt` and `tls.key` files in your current directory. If you don't have real certificates, you can generate self-signed ones for testing).*
```bash
gcloud secrets create creative-studio-dev-tls-crt \
  --replication-policy=automatic --data-file=./tls.crt

gcloud secrets create creative-studio-dev-tls-key \
  --replication-policy=automatic --data-file=./tls.key
```

---

## Step 5: Build the Infrastructure (Terraform)
Now we'll use Terraform to actually build the databases, networks, and Kubernetes cluster in the cloud.

```bash
# Move into the infrastructure folder
cd infra/environments/dev

# (If this is your first time, copy the example variables file and fill in your details)
cp dev.tfvars.example dev.tfvars

# Initialize Terraform
terraform init

# Build the infrastructure! (This might take 15-20 minutes)
terraform apply -var-file=dev.tfvars
```
*✨ **Magic Note**: When this finishes, Terraform will automatically generate a file called `generated/values-from-tf.yaml`. This file contains all the IP addresses and service account emails our application needs. You don't need to touch it!*

---

## Step 6: Deploy the Application (Helm)
Now that our servers exist, we need to put our Creative Studio code onto them using Helm.

```bash
# Move back to the root directory, then into the helm folder
cd ../../../

# Deploy the application using Helm!
helm upgrade --install creative-studio deploy/helm/creative-studio \
  -n creative-studio --create-namespace \
  -f infra/environments/dev/generated/values-from-tf.yaml \
  -f deploy/helm/creative-studio/values-dev.yaml
```

**Check if it worked:**
You can watch the pods (containers) start up by running:
```bash
kubectl -n creative-studio get pods -w
```
Wait until everything says `Running`. Press `Ctrl+C` to exit the watch mode.

---

## Step 7: Access the Website!
Your app is now running in the cloud! To visit it in your browser, we need to find its public IP address.

**1. Find the IP address:**
```bash
kubectl -n creative-studio get ingress creative-studio
```
Look under the `ADDRESS` column. Let's say it prints `34.13.79.67`.

**2. Point your domain to this IP:**
If you own the domain (e.g., `creative-studio.ravitiwary.altostrat.com`), go to your DNS provider (like Google Cloud DNS or GoDaddy) and create an **A Record** pointing to `34.13.79.67`.

**Shortcut for testing (Local Hosts File):**
If you don't want to wait for DNS to update, you can trick your computer into routing to it immediately:
1. Open your hosts file (`/etc/hosts` on Mac/Linux, or `C:\Windows\System32\drivers\etc\hosts` on Windows) as an Administrator.
2. Add this line at the bottom:
   `34.13.79.67    creative-studio.ravitiwary.altostrat.com`

**3. Open your browser!**
Go to `https://creative-studio.ravitiwary.altostrat.com`. You should see the Creative Studio login screen! 🎉

---

### Need to troubleshoot?
If a pod crashes or fails to start, you can read its logs to see what went wrong:
```bash
kubectl -n creative-studio logs deploy/creative-studio-backend -c app -f
```
