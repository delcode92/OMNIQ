import json
from omniq import OmniQClient


client = OmniQClient()

response = client.chat_completions_create(
    model="gpt-4o-mini",
    messages=[
        {"role": "user", "content": "what is cat ?"}
    ],
    stream=True,
    max_tokens=50
)
#
# print(json.dumps(response, indent=2))



chunk_count = 0
for chunk in response:
    chunk_count += 1
    print(f"Chunk {chunk_count}: {json.dumps(chunk)}")
