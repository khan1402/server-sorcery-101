# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Server Sorcery 101 - 4 VM environment
#   load-balancer  -> public-facing entry point (only VM reachable from host browser)
#   web-server-1/2 -> stateless request handlers, only reachable from load-balancer
#   app-server     -> core application logic, only reachable from web servers
#
# All VMs sit on a private host-only network (192.168.56.0/24) with static IPs.

IMAGE = "ubuntu/jammy64"

# Path to the PUBLIC key you want installed for the 'devops' user.
# Generate one first if you don't have it: ssh-keygen -t ed25519 -f ~/.ssh/devops_key
SSH_PUB_KEY_PATH = File.expand_path("~/.ssh/devops_key.pub")

NODES = {
  "load-balancer" => { ip: "192.168.56.10", cpus: 2, memory: 1024, role: "load-balancer" },
  "web-server-1"  => { ip: "192.168.56.11", cpus: 1, memory: 1024, role: "web-server"     },
  "web-server-2"  => { ip: "192.168.56.12", cpus: 1, memory: 1024, role: "web-server"     },
  "app-server"    => { ip: "192.168.56.13", cpus: 2, memory: 2048, role: "app-server"     },
}

unless File.exist?(SSH_PUB_KEY_PATH)
  abort "SSH public key not found at #{SSH_PUB_KEY_PATH}.\n" \
        "Generate one first:  ssh-keygen -t ed25519 -f ~/.ssh/devops_key"
end

Vagrant.configure("2") do |config|
  config.vm.boot_timeout = 600
  NODES.each do |name, opts|
    config.vm.define name do |node|
      node.vm.box = IMAGE
      node.vm.hostname = name

      node.vm.network "private_network", ip: opts[:ip]

      # Only the load balancer is exposed to the host machine / outside world.
      if name == "load-balancer"
        node.vm.network "forwarded_port", guest: 80, host: 8080, auto_correct: true
      end

      node.vm.provider "virtualbox" do |vb|
        vb.name   = "server-sorcery-#{name}"
        vb.cpus   = opts[:cpus]
        vb.memory = opts[:memory]
      end

      # Drop the devops public key onto the box so common.sh can install it
      node.vm.provision "file",
        source: SSH_PUB_KEY_PATH,
        destination: "/tmp/devops_key.pub"

      # Baseline hardening + user setup, applied to every VM
      node.vm.provision "shell", path: "scripts/common.sh", args: [name]

      # Role-specific configuration
      node.vm.provision "shell", path: "scripts/role-#{opts[:role]}.sh"
    end
  end
end
