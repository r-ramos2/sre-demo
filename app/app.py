from flask import Flask, jsonify
from prometheus_client import start_http_server, Counter
app = Flask(__name__)
REQUESTS = Counter("app_requests_total", "Total HTTP requests")
@app.before_request
def count_requests():
 REQUESTS.inc()
@app.route("/health")
def health():
 return jsonify(status="ok")
@app.route("/")
def index():
 return jsonify(message="Hello from SRE demo")
if __name__ == "__main__":
 start_http_server(9090)
 app.run(host="0.0.0.0", port=8080)