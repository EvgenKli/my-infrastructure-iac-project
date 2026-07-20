#. ЭТАП 1. Настройка провайдеров, авторизация, создание сервера

# 1. Настраиваем провайдеров
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    selectel  = {
      source  = "selectel/selectel"
      version = "~> 7.1.0"
    }
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54.0"
    }
  }
}

# 2. Глобальная авторизация в Selectel
provider "selectel" {
  domain_name = "486809"
  username    = "evgenkli"
  password    = var.selectel_password
  auth_region = "ru-2"
  auth_url    = "https://cloud.api.selcloud.ru/identity/v3/"
}

# 3. Создаем проект и выделяем под него ресурсы (квоты)
resource "selectel_vpc_project_v2" "msk_backend_project" {
  name = "msk-backend-project"

  quotas {
    resource_name = "compute_cores"
    resource_quotas {
      region = "ru-2"
      zone   = "ru-2a"
      value  = 12
    }
  }
  quotas {
    resource_name = "compute_ram"
    resource_quotas {
      region = "ru-2"
      zone   = "ru-2a"
      value  = 20480
    }
  }
  quotas {
    resource_name = "volume_gigabytes_fast"
    resource_quotas {
      region = "ru-2"
      zone   = "ru-2a"
      value  = 100
    }
  }
}

# 4. Настраиваем OpenStack с привязкой к созданному проекту
provider "openstack" {
  auth_url    = "https://cloud.api.selcloud.ru/identity/v3/"
  domain_name = "486809"
  tenant_id   = selectel_vpc_project_v2.msk_backend_project.id
  user_name   = "evgenkli"
  password    = var.selectel_password
  region      = "ru-2"
}

# 5.1. Создаем внутреннюю сеть для проекта
resource "openstack_networking_network_v2" "network" {
  name           = "backend-network"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "subnet" {
  name       = "backend-subnet"
  network_id = openstack_networking_network_v2.network.id
  cidr       = "192.168.10.0/24"
  ip_version = 4
}

# 5.2 Находим внешнюю сеть интернета в Selectel
data "openstack_networking_network_v2" "external_network" {
  external = true
}

# 5.3 Создаем виртуальный роутер
resource "openstack_networking_router_v2" "router" {
  name                = "backend-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external_network.id
}

# 5.4 Соединяем роутер с приватной подсетью
resource "openstack_networking_router_interface_v2" "router_interface" {
  router_id = openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.subnet.id
}

# 5.5 Выделяем публичный IP-адрес
resource "openstack_networking_floatingip_v2" "floating_ip" {
  pool = "external-network"
}

resource "openstack_networking_floatingip_associate_v2" "fip_associate" {
  floating_ip = openstack_networking_floatingip_v2.floating_ip.address
  port_id     = openstack_networking_port_v2.backend_port.id
  depends_on  = [openstack_networking_router_interface_v2.router_interface]
}

# Выделяем публичный IP master-ноде
resource "openstack_networking_floatingip_v2" "master_floating_ip" {
  pool = "external-network"
}

resource "openstack_networking_floatingip_associate_v2" "master_fip_associate" {
  floating_ip = openstack_networking_floatingip_v2.master_floating_ip.address
  port_id     = openstack_networking_port_v2.k8s_master_port.id
  depends_on  = [openstack_networking_router_interface_v2.router_interface]
}

# 5.6 Создаем сетевой порт и вешаем группы безопасности
resource "openstack_networking_port_v2" "backend_port" {
  name               = "backend-server-port"
  network_id         = openstack_networking_network_v2.network.id
  admin_state_up     = true
  security_group_ids = [openstack_networking_secgroup_v2.secgroup_db.id]
}

# Порт для Мастер-ноды K8s в Москве
resource "openstack_networking_port_v2" "k8s_master_port" {
  name               = "k8s-master-port"
  network_id         = openstack_networking_network_v2.network.id
  admin_state_up     = true
  security_group_ids = [openstack_networking_secgroup_v2.secgroup_db.id]
}

# Порт для Воркер-ноды K8s в Питере
resource "openstack_networking_port_v2" "k8s_worker_port" {
  name               = "k8s-worker-port"
  network_id         = openstack_networking_network_v2.network.id
  admin_state_up     = true
  security_group_ids = [openstack_networking_secgroup_v2.secgroup_db.id]
}

# 6.1 Объявляем ID образа операционной системы
data "openstack_images_image_v2" "ubuntu" {
  name        = "Ubuntu 24.04 LTS 64-bit"
  most_recent = true
}

# 6.2 Добавляем SSH-ключ
resource "openstack_compute_keypair_v2" "my_keypair" {
  name       = "vboxuser-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDIw3uKHjqpFpk+Atd7Y5IPFJm4iczxT15tZZ5O7evpk4SO/0276XYy950/aQE0M9H0DhuNX7TgOD+YsWhyOqaFNAIik7WYy5H75Lv/iJn5xJcBVvLRqKsmSTXd2fv4g4kpYfMsXLBu5pWZg+MmJLJuR6uZ5kCgnW1LVA2oXb9xLtI1IenckFowUQ1bgyAfmmrcHBYcppTG/IAFtI701a9CtfUgUQRn54OlPH83IQdriHiBnviFPwtiFtHWQzweISwPYL952RG+g2+08didwXLKrHPUXxtbTKxMEQLbr/XnZpt5oRdWETKsJ55cqzFxga88Hcx3wZ+bcmJPJWNXQEFr vboxuser@LinuxServer"
}

# 6.3 Создаем группу безопасности для файрвола OpenStack
resource "openstack_networking_secgroup_v2" "secgroup_db" {
  name        = "db-security-group"
  description = "Allow PostgreSQL and SSH traffic"
}

# 6.4 Добавляем правило: разрешить входящий порт 5432 (PostgreSQL) со всего интернета
resource "openstack_networking_secgroup_rule_v2" "allow_postgres" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5432
  port_range_max    = 5432
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_db.id
}

# 6.5 Добавляем правило: разрешить входящий порт 6443 (Kubernetes API) со всего интернета
resource "openstack_networking_secgroup_rule_v2" "allow_k8s_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_db.id
}

# 6.6 Добавляем правило: разрешить входящий порт 2379-2380 (etcd) со всего интернета
resource "openstack_networking_secgroup_rule_v2" "allow_k8s_etcd" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 2379
  port_range_max    = 2380
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_db.id
}

# 6.7 Добавляем правило: разрешить входящий порт 10250 (Kubelet) со всего интернета
resource "openstack_networking_secgroup_rule_v2" "allow_k8s_let" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 10250
  port_range_max    = 10250
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_db.id
}

# 6.8 Разрешаем входящий SSH со всего интернета
resource "openstack_networking_secgroup_rule_v2" "allow_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_db.id
}

# 6.9 Добавляем правило: разрешить входящий порт 8080-8099 (Port Forwarding) со всего интернета
resource "openstack_networking_secgroup_rule_v2" "allow_k8s_port_forward" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8080
  port_range_max    = 8099
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_db.id
}

# 6.10 Добавляем правило: разрешить входящий порт 3000 (Grafana) со всего интернета
resource "openstack_networking_secgroup_rule_v2" "allow_grafana_port" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3000
  port_range_max    = 3000
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_db.id
}

# 6.11 Добавляем правило: разрешить входящий порт 9090 (Prometheus) со всего интернета
resource "openstack_networking_secgroup_rule_v2" "allow_prometheus_port" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 9090
  port_range_max    = 9090
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_db.id
}

# 6.11 Добавляем правило: разрешить входящий порт 9100 (Monitoring) строго по локальной сети
resource "openstack_networking_secgroup_rule_v2" "allow_monitoring_port" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 9100
  port_range_max    = 9100
  remote_ip_prefix  = "192.168.10.0/24"
  security_group_id = openstack_networking_secgroup_v2.secgroup_db.id
}

# 7. Сервер 1. Создаем msk_backend
resource "openstack_compute_instance_v2" "msk_backend" {
  name              = "msk-backend-node"
  region            = "ru-2"
  availability_zone = "ru-2a"
  flavor_name       = "BL1.1-2048"
  key_pair          = openstack_compute_keypair_v2.my_keypair.name

  network {
    port = openstack_networking_port_v2.backend_port.id
  }

  block_device {
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = 20
    boot_index            = 0
    delete_on_termination = true
    uuid                  = data.openstack_images_image_v2.ubuntu.id
    volume_type           = "fast.ru-2a"
  }
}

# Сервер 2. Создаем K8s Master Node
resource "openstack_compute_instance_v2" "k8s_master" {
  name              = "msk-k8s-master"
  region            = "ru-2"
  availability_zone = "ru-2a"
  flavor_name       = "SL1.2-4096"
  key_pair          = openstack_compute_keypair_v2.my_keypair.name

  network {
    port = openstack_networking_port_v2.k8s_master_port.id
  }

  block_device {
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = 20
    boot_index            = 0
    delete_on_termination = true
    uuid                  = data.openstack_images_image_v2.ubuntu.id
    volume_type           = "fast.ru-2a"
  }
}

# Севрер 3. Создаем K8s Worker Node
resource "openstack_compute_instance_v2" "k8s_worker" {
  name              = "spb-k8s-worker"
  region            = "ru-2"
  availability_zone = "ru-2b"
  flavor_name       = "SL1.2-4096"
  key_pair          = openstack_compute_keypair_v2.my_keypair.name

  network {
    port = openstack_networking_port_v2.k8s_worker_port.id
  }

  block_device {
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = 20
    boot_index            = 0
    delete_on_termination = true
    uuid                  = data.openstack_images_image_v2.ubuntu.id
    volume_type           = "fast.ru-2b"
  }
}

# Выводим публичный адрес на экран
output "backend_public_ip" {
  value       = openstack_networking_floatingip_v2.floating_ip.address
  description = "Public IP address of our cloud backend server"
}

# Выводим IP адрес Мастера на экран
output "k8s_master_public_ip" {
  value       = openstack_networking_floatingip_v2.master_floating_ip.address
  description = "Public IP of Kubernetes Master Node"
}
