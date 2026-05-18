import vertexai
from vertexai.generative_models import GenerativeModel
from vertexai.preview.vision_models import ImageGenerationModel

vertexai.init(project='ravi-argolis-01', location='us-central1')

models_to_test = [
    "gemini-1.5-flash",
    "gemini-1.5-pro",
    "gemini-2.0-flash-exp",
    "gemini-2.5-flash-image",
    "gemini-3.1-flash-image-preview",
    "imagen-3.0-generate-001",
    "imagen-3.0-generate-002",
    "veo-2.0-generate-001",
    "veo-3.1-generate-001",
    "veo-3.1-lite-generate-001"
]

print("Testing Model Availability...")
for model_name in models_to_test:
    try:
        if 'imagen' in model_name or 'image' in model_name:
            if 'gemini' in model_name:
               model = GenerativeModel(model_name)
               model.generate_content("hello")
               print(f"✅ {model_name} (Gemini image model check)")
            else:
               model = ImageGenerationModel.from_pretrained(model_name)
               print(f"✅ {model_name} (Imagen check)")
        else:
            model = GenerativeModel(model_name)
            model.generate_content("hello")
            print(f"✅ {model_name} (Gemini check)")
    except Exception as e:
        print(f"❌ {model_name}: {e}")

