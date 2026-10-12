student_name = "rose"

# Docker network segments
networks = ["devops", "internal", "web"]

corp_octet = 70

cloud_image_path = "/opt/images/ubuntu22.04.qcow2"
win_server_image_path = "/opt/images/win2k25.qcow2"
win11_image_path = "/opt/images/win11.qcow2"

user_data = templatefile("${path.module}/cloud-init-server.yaml", {
  hostname       = each.key                    # e.g. jsmith-ubuntu-srv
  student_name   = var.student_name          # e.g. jsmith
  ssh_public_key = tls_private_key.deploy.public_key_openssh
})

vms = {
  "rose-win-srv" = {
    os = "win-server"
  }
  "rose-win11" = {
    os = "win11"
  }
  "rose-ubuntu-srv" = {
    os        = "ubuntu-server"
    memory_mb = 2048
    vcpu      = 1
  }
}

services = {
  gitea = {
    image   = "gitea/gitea:latest"
    network = "devops"
    ports = [
      { internal = 3000, external = 3000 }
    ]
  }

  wordpress = {
    image = "wordpress:latest"
    network = "web"
    ports = [
      { internal = 80, external = 3007 }
    ]
  env = {
      WORDPRESS_DB_HOST     = "rose-mysql"
      WORDPRESS_DB_USER     = "wpuser"
      WORDPRESS_DB_PASSWORD = "wppass"
      WORDPRESS_DB_NAME     = "wordpress"
    }
  }

  mysql = {
    image   = "mysql:8.0"
    network = "web"
    ports = [{ internal = 3306, external = 3006 }]
    env = {
      MYSQL_ROOT_PASSWORD = "rootpass"
      MYSQL_DATABASE      = "wordpress"
      MYSQL_USER          = "wpuser"
      MYSQL_PASSWORD      = "wppass"
    }
  }
  
  drawio = {
  	image	= "jgraph/drawio:latest"
  	network	= "devops"
  	ports	= [{ internal = 8080, external = 3001 }]
  }
  
  vaultwarden = {
  	image	= "vaultwarden/server:latest"
  	network = "internal"
  	ports	= [{ internal = 80, external = 3002 }]
  	env 	= {
  		ADMIN_TOKEN = "wowzers"
  		I_REALLY_WANT_VOLATILE_STORAGE=true
  	}
  }
  
  stirlingpdf = {
  	image = "frooodle/s-pdf:latest"
  	network = "internal"
  	ports = [{ internal = 8080, external = 3003 }]
  }
  
  privatebin = {
  	image 	= "privatebin/nginx-fpm-alpine:latest"
  	network = "internal"
  	ports 	= [{ internal = 8080, external = 3004 }]
  }
  
  excalidraw = {
  	image 	= "excalidraw/excalidraw"
  	network = "internal"
  	ports 	= [{ internal = 5000, external = 3005}]
  }
  
  logseq = {
  	image 	= "ghcr.io/logseq/logseq-webapp:latest"
  	network	= "web"
  	ports 	= [{ internal= 3010, external = 3008 }]
  }
}

