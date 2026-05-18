from google.cloud import aiplatform
aiplatform.init(project='ravi-argolis-01', location='us-central1')
from google.cloud.aiplatform.gapic import ModelServiceClient

client = ModelServiceClient()
request = {"parent": "projects/ravi-argolis-01/locations/us-central1/publishers/google", "page_size": 1000}

models = []
try:
    for model in client.list_publisher_models(request=request):
        name = model.name.split('/')[-1]
        if 'gemini' in name or 'imagen' in name or 'veo' in name:
            models.append(name)
    print("Available Gen AI Models:")
    for m in sorted(models):
        print(f" - {m}")
except Exception as e:
    print(f"Error: {e}")
