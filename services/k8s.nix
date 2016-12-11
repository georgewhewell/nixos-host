{ config, lib, pkgs, ... }:

let
  runWithOpenSSL = file: cmd: pkgs.runCommand file {
        buildInputs = [ pkgs.openssl ];
      } cmd;
  ca_key = runWithOpenSSL "ca-key.pem" "openssl genrsa -out $out 2048";
  ca_pem = runWithOpenSSL "ca.pem" ''
    openssl req \
      -x509 -new -nodes -key ${ca_key} \
      -days 10000 -out $out -subj "/CN=etcd-ca"
  '';
  etcd_key = runWithOpenSSL "etcd-key.pem" "openssl genrsa -out $out 2048";
  etcd_csr = runWithOpenSSL "etcd.csr" ''
    openssl req \
      -new -key ${etcd_key} \
      -out $out -subj "/CN=etcd" \
      -config ${openssl_cnf}
  '';
  etcd_cert = runWithOpenSSL "etcd.pem" ''
    openssl x509 \
      -req -in ${etcd_csr} \
      -CA ${ca_pem} -CAkey ${ca_key} \
      -CAcreateserial -out $out \
      -days 365 -extensions v3_req \
      -extfile ${openssl_cnf}
  '';
  etcd_client_key = runWithOpenSSL "etcd-client-key.pem"
    "openssl genrsa -out $out 2048";
  etcd_client_csr = runWithOpenSSL "etcd-client-key.pem" ''
    openssl req \
      -new -key ${etcd_client_key} \
      -out $out -subj "/CN=etcd-client" \
      -config ${client_openssl_cnf}
  '';
  etcd_client_cert = runWithOpenSSL "etcd-client.crt" ''
    openssl x509 \
      -req -in ${etcd_client_csr} \
      -CA ${ca_pem} -CAkey ${ca_key} -CAcreateserial \
      -out $out -days 365 -extensions v3_req \
      -extfile ${client_openssl_cnf}
  '';
  apiserver_key = runWithOpenSSL "apiserver-key.pem" ''
    export RANDFILE="$out/.rnd"
    openssl genrsa -out $out 2048
  '';
  apiserver_csr = runWithOpenSSL "apiserver.csr" ''
    export RANDFILE="$out/.rnd"
    openssl req \
      -new -key ${apiserver_key} \
      -out $out -subj "/CN=kube-apiserver" \
      -config ${apiserver_cnf}
  '';
  apiserver_cert = runWithOpenSSL "apiserver.pem" ''
    export RANDFILE="$out/.rnd"
    openssl x509 \
      -req -in ${apiserver_csr} \
      -CA ${ca_pem} -CAkey ${ca_key} -CAcreateserial \
      -out $out -days 365 -extensions v3_req \
      -extfile ${apiserver_cnf}
  '';
  worker_key = runWithOpenSSL "worker-key.pem" ''
      export RANDFILE="$out/.rnd"
      openssl genrsa -out $out 2048
  '';
  worker_csr = runWithOpenSSL "worker.csr" ''
    openssl req \
      -new -key ${worker_key} \
      -out $out -subj "/CN=kube-worker" \
      -config ${worker_cnf}
  '';

  worker_cert = runWithOpenSSL "worker.pem" ''
    openssl x509 \
      -req -in ${worker_csr} \
      -CA ${ca_pem} -CAkey ${ca_key} -CAcreateserial \
      -out $out -days 365 -extensions v3_req \
      -extfile ${worker_cnf}
  '';
  openssl_cnf = pkgs.writeText "openssl.cnf" ''
    [req]
    req_extensions = v3_req
    distinguished_name = req_distinguished_name
    [req_distinguished_name]
    [ v3_req ]
    basicConstraints = CA:FALSE
    keyUsage = digitalSignature, keyEncipherment
    extendedKeyUsage = serverAuth
    subjectAltName = @alt_names
    [alt_names]
    DNS.1 = tsar.su
    IP.1 = 127.0.0.1
  '';
  client_openssl_cnf = pkgs.writeText "client-openssl.cnf" ''
    [req]
    req_extensions = v3_req
    distinguished_name = req_distinguished_name
    [req_distinguished_name]
    [ v3_req ]
    basicConstraints = CA:FALSE
    keyUsage = digitalSignature, keyEncipherment
    extendedKeyUsage = clientAuth
  '';
  apiserver_cnf = pkgs.writeText "apiserver-openssl.cnf" ''
    [req]
    req_extensions = v3_req
    distinguished_name = req_distinguished_name
    [req_distinguished_name]
    [ v3_req ]
    basicConstraints = CA:FALSE
    keyUsage = nonRepudiation, digitalSignature, keyEncipherment
    subjectAltName = @alt_names
    [alt_names]
    DNS.1 = kubernetes
    DNS.2 = kubernetes.default
    DNS.3 = kubernetes.default.svc
    DNS.4 = kubernetes.default.svc.cluster.local
    DNS.5 = tsar.su
    IP.1 = 10.10.0.1
  '';
  worker_cnf = pkgs.writeText "worker-openssl.cnf" ''
      [req]
      req_extensions = v3_req
      distinguished_name = req_distinguished_name
      [req_distinguished_name]
      [ v3_req ]
      basicConstraints = CA:FALSE
      keyUsage = nonRepudiation, digitalSignature, keyEncipherment
      subjectAltName = @alt_names
      [alt_names]
      DNS.1 = kubeWorker1
      DNS.2 = kubeWorker2
      DNS.3 = tsar.su
    '';
in {
  networking = {
    bridges = {
      cbr0.interfaces = [];
    };
    interfaces.cbr0 = {};
    firewall.trustedInterfaces = [ "crb0" ];
    firewall.checkReversePath = false;
    firewall.allowedTCPPorts = [ 80 443 ];
  };

  virtualisation.docker = {
    enable = true;
    storageDriver = "zfs";
    socketActivation = false;
    extraOptions = "--iptables=false --ip-masq=false -b cbr0";
  };

  services.etcd = {
      enable = true;
      keyFile = etcd_key;
      certFile = etcd_cert;
      trustedCaFile = ca_pem;
      peerClientCertAuth = true;
      listenClientUrls = ["https://0.0.0.0:2379"];
  };

  services.kubernetes = {
    apiserver = {
      publicAddress = "0.0.0.0";
      securePort = 8443;
      advertiseAddress = "10.10.0.1";
      tlsKeyFile = apiserver_key;
      tlsCertFile = apiserver_cert;
      clientCaFile = ca_pem;
      kubeletClientCaFile = ca_pem;
      kubeletClientKeyFile = worker_key;
      kubeletClientCertFile = worker_cert;
    };

    etcd = {
       servers = ["https://127.0.0.1:2379" ];
       keyFile = etcd_client_key;
       certFile = etcd_client_cert;
       caFile = ca_pem;
    };

    kubelet = {
      tlsKeyFile = worker_key;
      tlsCertFile = worker_cert;
    };

    scheduler = {
      enable = true;
    };

    controllerManager = {
      enable = true;
      rootCaFile = ca_pem;
      serviceAccountKeyFile = worker_key;
    };

    kubeconfig = {
      server = "https://tsar.su:8443";
      caFile = ca_pem;
      certFile = worker_cert;
      keyFile = worker_key;
    };

    dns.enable = true;

    roles = ["master" "node"];
  };

}
