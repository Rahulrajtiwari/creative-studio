import vertexai
from vertexai.generative_models import GenerativeModel

try:
    vertexai.init(project='ravi-argolis-01', location='global')
    model = GenerativeModel("gemini-1.5-flash")
    model.generate_content("hello")
    print("✅ Success")
except Exception as e:
    print(f"❌ Error: {e}")

