# Docker


## Use multipass to get a virtual env 

```bash
# --- Multipass ---
# Used to not change my local docker install, multipass allow me to create virtual env
# where I will setup a fresh docker swarm cluster

# Get the lastest LTS release
multipass find
# Start the virtual environnement
multipass launch 25.04 --name u25 --memory 8G --disk 20G --cpus 2
multipass shell u25

# Multipass memo:
multipass list
multipass stop
multipass delete --purge u25

# --- Docker swarm ---
# Install docker according to the documention :https://docs.docker.com/engine/install/
alias docker='sudo docker'
alias docker-compose='sudo docker-compose'

# Init the swarm cluster
docker swarm init
# Optionnal : Install the loki docker log driver
docker plugin install grafana/loki-docker-driver:3.3.2-arm64 --alias loki --grant-all-permissions

# --- Setup ---
# Optionnal : Use grafana to visualize the loki log
docker run -d --name=grafana --network host \
    -e GF_SECURITY_ADMIN_USER=admin \
    -e GF_SECURITY_ADMIN_PASSWORD=admin \
    grafana/grafana:12.2
# Acces to grafana with http://<MULTIPASS_INSTANCE_IP>:3000/

# Install MinIO Bucket service
docker run -d --name minio -p "9000:9000" -p "9001:9001" \
-e "MINIO_ROOT_USER"=admin -e "MINIO_ROOT_PASSWORD"=admin123 \
minio/minio:latest server /minio_data --console-address ":9001"
# Acces to MinIO : http://<MULTIPASS_INSTANCE_IP>:9001/browser/
# and create a bucket named "loki"

# Start loki
docker run -d --name loki --network host \
-v /home/ubuntu/loki-config.yml:/etc/loki/local-config.yaml \
grafana/loki:3.5 -config.file=/etc/loki/local-config.yaml -config.expand-env=true
# Acces to loki : http://<MULTIPASS_INSTANCE_IP>:3100/config
# Acces to loki : http://<MULTIPASS_INSTANCE_IP>:3100/services
# Acces to loki : http://<MULTIPASS_INSTANCE_IP>:3100/ready
# Acces to loki : http://<MULTIPASS_INSTANCE_IP>:3100/loki/api/v1/labels?since=30d


# Check if loki did start well
docker logs loki

# Generate 250k line of logs and insert them into loki
docker run -d --network host python:3.14 bash -c "pip install python-logging-loki && time python -c \"import logging,logging_loki,random; logging.basicConfig(format=\\\"%(asctime)s | %(levelname)s | %(message)s\\\",level=logging.INFO,datefmt=\\\"%Y-%m-%d %H:%M:%S\\\");logger = logging.getLogger(\\\"python-log\\\");handler=logging_loki.LokiHandler(url=\\\"http://127.0.0.1:3100/loki/api/v1/push\\\", version=\\\"1\\\",tags={\\\"service\\\": \\\"python\\\"},);logger.addHandler(handler);[(logger.error(f\\\"{ ('POST','GET')[random.randint(0, 1)] } /{('inbox','admin','admin','admin','settings','core','core','hr','helpdesk','ticket')[random.randint(0, 9)]}{('/new_notifications','','/ticket','/comments','/test','/1')[random.randint(0, 5)]}{('.css','','.js','.txt','.html','.html','.html','.jpeg')[random.randint(0, 7)]} http {(500,501,502,504)[random.randint(0, 3)] } {random.randint(1, 256)} https://python.app.com (user:{random.randint(1, 256)})\\\") if random.random() < 0.7 else logger.warning(f\\\"{ ('POST','GET')[random.randint(0, 1)] } /{('inbox','admin','admin','admin','settings','core','core','hr','helpdesk','ticket')[random.randint(0, 9)]}{('/new_notifications','','/ticket','/comments','/test','/1')[random.randint(0, 5)]}{('.css','','.js','.txt','.html','.html','.html','.jpeg')[random.randint(0, 7)]} http {(400,401,403,404)[random.randint(0, 3)] } {random.randint(1, 256)} https://python.app.com (user:{random.randint(1, 256)})\\\")) if random.random() < 0.05 else logger.info(f\\\"{ ('POST','GET')[random.randint(0, 1)] } /{('inbox','admin','admin','admin','settings','core','core','hr','helpdesk','ticket')[random.randint(0, 9)]}{('/new_notifications','','/ticket','/comments','/test','/1')[random.randint(0, 5)]}{('.css','','.js','.txt','.html','.html','.html','.jpeg')[random.randint(0, 7)]} http {(200,201,301,302)[random.randint(0, 3)] } {random.randint(1, 256)} https://python.app.com (user:{random.randint(1, 256)})\\\") for i in range(250000)]\""


# --log-driver=loki \
# --log-opt loki-url="http://127.0.0.1:3100/loki/api/v1/push" \
# --log-opt loki-retries=5 \
# --log-opt loki-batch-size=400 \
# --log-opt keep-file="true" \
# --log-opt mode="non-blocking" \
```
