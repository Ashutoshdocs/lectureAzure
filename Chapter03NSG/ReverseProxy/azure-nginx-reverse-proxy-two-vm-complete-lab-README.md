# Azure Nginx Reverse Proxy --- Complete Two-VM Lab

## VM-1: Public Nginx Reverse Proxy \| VM-2: Private Backend Web Server

This lab deploys exactly two Ubuntu VMs in Azure:

-   **VM-1 (`vm-nginx`)**: Public-facing Nginx reverse proxy.
-   **VM-2 (`vm-backend`)**: Private Apache web server with no public
    IP.
-   **NSGs**: Allow administration and public web traffic to VM-1, and
    backend HTTP only from the proxy subnet.
-   **Nginx**: Supports HTTP reverse proxying, Basic Authentication,
    forwarded headers, and optional HTTPS with Certbot.

> This is a production-oriented learning baseline, not a
> high-availability architecture. A single Nginx VM is a single point of
> failure. Production should use multiple proxy instances behind Azure
> Load Balancer or Application Gateway, with monitoring and tested
> recovery.

------------------------------------------------------------------------

## 1. Architecture

``` text
                 Internet / Browser
                         |
                  TCP 80 / 443
                         |
                 VM-1 Public IP
             +----------------------+
             | VM-1: vm-nginx       |
             | Ubuntu + Nginx       |
             | Public IP: Yes       |
             | 10.70.1.x            |
             | Reverse proxy        |
             | Basic Auth (optional)|
             | TLS termination      |
             +----------------------+
                         |
                  Private HTTP :80
                         |
             +----------------------+
             | VM-2: vm-backend     |
             | Ubuntu + Apache      |
             | 10.70.2.x            |
             | Public IP: No        |
             +----------------------+

       VNet: 10.70.0.0/16
       snet-proxy:   10.70.1.0/24
       snet-backend: 10.70.2.0/24

NSG-Proxy:
  TCP 22 from admin IP only
  TCP 80/443 from intended client ranges

NSG-Backend:
  TCP 80 from proxy subnet only
  TCP 22 from proxy subnet for jump-host administration
```

### Request flow

1.  Browser connects to VM-1's public IP or DNS name.
2.  Nginx receives the HTTP/HTTPS request.
3.  If enabled, Nginx challenges the user for Basic Authentication.
4.  Nginx creates a separate HTTP request to VM-2's private IP.
5.  VM-2 returns the response to Nginx.
6.  Nginx returns the response to the browser.

The browser connects to VM-1, not directly to VM-2. Nginx operates at
Layer 7 (HTTP/HTTPS). This is not IP forwarding or DNAT port forwarding.

------------------------------------------------------------------------

## 2. Prerequisites and variables

Requirements: - Azure subscription and permission to create resource
groups, VNets, subnets, NSGs, VMs, and public IPs. - Azure CLI
installed. - SSH key pair. - Your current public IPv4 address in CIDR
format. - Optional: a DNS name you control for HTTPS.

Sign in:

``` bash
az login
az account show --output table
az account set --subscription "<SUBSCRIPTION_ID>"
```

Set variables. Replace the admin IP placeholder with your real public
IP, for example `203.0.113.10/32` is only a documentation example:

``` bash
LOCATION="centralindia"
RG="rg-nginx-reverse-proxy"

VNET="vnet-nginx-demo"
PROXY_SUBNET="snet-proxy"
BACKEND_SUBNET="snet-backend"

NSG_PROXY="nsg-proxy"
NSG_BACKEND="nsg-backend"

VM_PROXY="vm-nginx"
VM_BACKEND="vm-backend"

ADMIN_CIDR="YOUR_PUBLIC_IP/32"
SSH_PUBLIC_KEY="$HOME/.ssh/id_rsa.pub"
```

Verify the SSH public key exists:

``` bash
test -f "$SSH_PUBLIC_KEY" || {
  echo "SSH public key not found: $SSH_PUBLIC_KEY"
  exit 1
}
```

Never expose SSH to `0.0.0.0/0`. Prefer Azure Bastion or another
approved private management path for production.

------------------------------------------------------------------------

## 3. Create resource group, VNet, and subnets

``` bash
az group create -n "$RG" -l "$LOCATION"

az network vnet create \
  -g "$RG" -n "$VNET" -l "$LOCATION" \
  --address-prefixes 10.70.0.0/16 \
  --subnet-name "$PROXY_SUBNET" \
  --subnet-prefixes 10.70.1.0/24

az network vnet subnet create \
  -g "$RG" --vnet-name "$VNET" \
  -n "$BACKEND_SUBNET" \
  --address-prefixes 10.70.2.0/24
```

------------------------------------------------------------------------

## 4. Create NSGs and rules

### 4.1 Proxy NSG

``` bash
az network nsg create -g "$RG" -n "$NSG_PROXY" -l "$LOCATION"

az network nsg rule create \
  -g "$RG" --nsg-name "$NSG_PROXY" \
  -n Allow-SSH-Admin --priority 100 \
  --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "$ADMIN_CIDR" \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 22

az network nsg rule create \
  -g "$RG" --nsg-name "$NSG_PROXY" \
  -n Allow-HTTP --priority 110 \
  --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes Internet \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 80

az network nsg rule create \
  -g "$RG" --nsg-name "$NSG_PROXY" \
  -n Allow-HTTPS --priority 120 \
  --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes Internet \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 443
```

For production, restrict HTTP/HTTPS source ranges if the application is
not public.

### 4.2 Backend NSG

``` bash
az network nsg create -g "$RG" -n "$NSG_BACKEND" -l "$LOCATION"

az network nsg rule create \
  -g "$RG" --nsg-name "$NSG_BACKEND" \
  -n Allow-HTTP-From-Proxy --priority 100 \
  --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes 10.70.1.0/24 \
  --source-port-ranges '*' \
  --destination-address-prefixes 10.70.2.0/24 \
  --destination-port-ranges 80

az network nsg rule create \
  -g "$RG" --nsg-name "$NSG_BACKEND" \
  -n Allow-SSH-From-Proxy --priority 110 \
  --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes 10.70.1.0/24 \
  --source-port-ranges '*' \
  --destination-address-prefixes 10.70.2.0/24 \
  --destination-port-ranges 22
```

Associate NSGs with the subnets:

``` bash
az network vnet subnet update \
  -g "$RG" --vnet-name "$VNET" -n "$PROXY_SUBNET" \
  --network-security-group "$NSG_PROXY"

az network vnet subnet update \
  -g "$RG" --vnet-name "$VNET" -n "$BACKEND_SUBNET" \
  --network-security-group "$NSG_BACKEND"
```

The backend HTTP rule allows only the proxy subnet. VM-2 will have no
public IP.

------------------------------------------------------------------------

## 5. Create VM-1 --- public Nginx proxy

``` bash
az vm create \
  -g "$RG" -n "$VM_PROXY" -l "$LOCATION" \
  --image Ubuntu2404 --size Standard_B1s \
  --vnet-name "$VNET" --subnet "$PROXY_SUBNET" \
  --nsg "" \
  --admin-username azureuser \
  --ssh-key-values "$SSH_PUBLIC_KEY" \
  --public-ip-sku Standard
```

Retrieve its IP addresses:

``` bash
PROXY_PRIVATE_IP=$(az vm show -d -g "$RG" -n "$VM_PROXY" --query privateIps -o tsv)
PROXY_PUBLIC_IP=$(az vm show -d -g "$RG" -n "$VM_PROXY" --query publicIps -o tsv)

echo "Proxy private IP: $PROXY_PRIVATE_IP"
echo "Proxy public IP:  $PROXY_PUBLIC_IP"
```

------------------------------------------------------------------------

## 6. Create VM-2 --- private backend

Create the backend VM without a public IP:

``` bash
az vm create \
  -g "$RG" -n "$VM_BACKEND" -l "$LOCATION" \
  --image Ubuntu2404 --size Standard_B1s \
  --vnet-name "$VNET" --subnet "$BACKEND_SUBNET" \
  --nsg "" \
  --public-ip-address "" \
  --admin-username azureuser \
  --ssh-key-values "$SSH_PUBLIC_KEY"
```

Retrieve its private IP:

``` bash
BACKEND_PRIVATE_IP=$(az vm show -d -g "$RG" -n "$VM_BACKEND" \
  --query privateIps -o tsv)

echo "Backend private IP: $BACKEND_PRIVATE_IP"
```

Confirm VM-2 has no public IP:

``` bash
az vm show -d -g "$RG" -n "$VM_BACKEND" \
  --query "{name:name,privateIps:privateIps,publicIps:publicIps}" -o table
```

Save these IP values. If using a new terminal later, retrieve them
again.

------------------------------------------------------------------------

## 7. Install Apache and create a page on VM-2

Use Azure Run Command to configure the private backend:

``` bash
az vm run-command invoke \
  -g "$RG" -n "$VM_BACKEND" \
  --command-id RunShellScript \
  --scripts '
    apt-get update
    apt-get install -y apache2
    cat > /var/www/html/index.html <<EOF
    <!DOCTYPE html>
    <html>
    <head><title>Private Backend VM</title></head>
    <body>
      <h1>Welcome to Backend VM-2</h1>
      <p>Served by Apache on a private Azure VM.</p>
      <p>Request reached this server through the Nginx reverse proxy.</p>
    </body>
    </html>
EOF
    systemctl enable --now apache2
    systemctl status apache2 --no-pager
  '
```

If package installation fails, check VM-2's outbound connectivity and
DNS. Do not expose the backend publicly to solve package installation
issues; use an approved update/egress path.

------------------------------------------------------------------------

## 8. Install Nginx on VM-1

SSH to VM-1:

``` bash
ssh azureuser@"$PROXY_PUBLIC_IP"
```

Install Nginx and tools for Basic Authentication:

``` bash
sudo apt-get update
sudo apt-get install -y nginx apache2-utils curl
sudo systemctl enable --now nginx
sudo systemctl status nginx --no-pager
```

The default Nginx page should be available at:

``` text
http://VM1_PUBLIC_IP
```

------------------------------------------------------------------------

## 9. Test private connectivity from VM-1 to VM-2

On VM-1:

``` bash
curl -I "http://BACKEND_PRIVATE_IP"
```

Replace `BACKEND_PRIVATE_IP` with the actual private IP retrieved in
Step 6.

Expected response includes `HTTP/1.1 200 OK` and an Apache server
header.

If it fails, check that: - VM-2 is running. - Apache is active. -
Backend NSG permits TCP 80 from `10.70.1.0/24`. - The backend private IP
is correct.

------------------------------------------------------------------------

## 10. Configure the Nginx reverse proxy

On VM-1, create a dedicated site:

``` bash
sudo nano /etc/nginx/sites-available/backend-proxy
```

Use this configuration, replacing `10.70.2.4` with the actual private IP
of VM-2:

``` nginx
server {
    listen 80;
    listen [::]:80;

    server_name _;

    location / {
        proxy_pass http://10.70.2.4:80;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 5s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

Enable the site and disable the default site:

``` bash
sudo ln -s /etc/nginx/sites-available/backend-proxy \
  /etc/nginx/sites-enabled/backend-proxy

sudo rm -f /etc/nginx/sites-enabled/default
```

Validate and reload:

``` bash
sudo nginx -t
sudo systemctl reload nginx
```

Open:

``` text
http://VM1_PUBLIC_IP
```

Expected page:

``` text
Welcome to Backend VM-2
Served by Apache on a private Azure VM.
Request reached this server through the Nginx reverse proxy.
```

The browser connects to VM-1. Nginx privately retrieves the content from
VM-2.

------------------------------------------------------------------------

## 11. Add Basic Authentication

Basic Authentication is suitable for a simple protected demo, but it is
not a replacement for enterprise SSO, MFA, or identity-aware access.

Create a password file:

``` bash
sudo htpasswd -c /etc/nginx/.htpasswd demo-user
```

Enter a strong password when prompted. Set permissions:

``` bash
sudo chown root:www-data /etc/nginx/.htpasswd
sudo chmod 640 /etc/nginx/.htpasswd
```

Edit the Nginx site:

``` bash
sudo nano /etc/nginx/sites-available/backend-proxy
```

Add these directives inside the `location /` block:

``` nginx
auth_basic "Restricted Access - Please Login";
auth_basic_user_file /etc/nginx/.htpasswd;
```

The full location block should look like:

``` nginx
location / {
    auth_basic "Restricted Access - Please Login";
    auth_basic_user_file /etc/nginx/.htpasswd;

    proxy_pass http://10.70.2.4:80;
    proxy_http_version 1.1;

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    proxy_connect_timeout 5s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
}
```

Replace the backend IP with the actual value. Then:

``` bash
sudo nginx -t
sudo systemctl reload nginx
```

Open the browser again. Nginx should prompt for username and password.
After successful authentication, it proxies the request to VM-2.

**Critical:** Basic Authentication over plain HTTP does not encrypt
credentials in transit. Use HTTPS before using Basic Authentication
outside an isolated temporary lab.

------------------------------------------------------------------------

## 12. Configure HTTPS for production

For a production deployment, use a DNS name you control, for example
`app.example.com`.

1.  Create an `A` record pointing `app.example.com` to VM-1's public IP.
2.  Confirm DNS resolves to VM-1.
3.  Ensure NSG permits inbound TCP 80 and 443.
4.  Update the Nginx `server_name` to your real domain.
5.  Obtain a trusted certificate with Certbot.

Install Certbot on VM-1:

``` bash
sudo apt-get update
sudo apt-get install -y certbot python3-certbot-nginx
```

Edit the site and replace:

``` nginx
server_name _;
```

with:

``` nginx
server_name app.example.com;
```

Then validate and reload:

``` bash
sudo nginx -t
sudo systemctl reload nginx
```

Request a certificate:

``` bash
sudo certbot --nginx -d app.example.com
```

Follow the prompts and select the HTTP-to-HTTPS redirect option when
offered.

Test renewal:

``` bash
sudo certbot renew --dry-run
```

Browse to:

``` text
https://app.example.com
```

Certbot requires the DNS name to resolve to VM-1 and its HTTP validation
path to be reachable. Use a real domain you control.

Certbot normally edits Nginx and installs certificate directives. Keep
the certificate paths and TLS settings it generates. A simplified target
layout is:

``` nginx
server {
    listen 80;
    server_name app.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name app.example.com;

    # Keep ssl_certificate and ssl_certificate_key
    # directives generated by Certbot.

    location / {
        auth_basic "Restricted Access - Please Login";
        auth_basic_user_file /etc/nginx/.htpasswd;

        proxy_pass http://10.70.2.4:80;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
```

Do not paste this simplified example over the working Certbot
configuration without preserving its actual certificate directives.

------------------------------------------------------------------------

## 13. Verify the setup

### Browser

``` text
http://VM1_PUBLIC_IP
https://app.example.com
```

The first is the temporary HTTP demo. Use the second only after
configuring DNS and HTTPS.

### Check Nginx from an administration terminal

``` bash
curl -I "http://$PROXY_PUBLIC_IP"
```

For the temporary HTTP Basic Auth demo, curl prompts for a password:

``` bash
curl -u demo-user "http://$PROXY_PUBLIC_IP"
```

Do not put passwords directly in shell history.

### Nginx service and logs on VM-1

``` bash
sudo systemctl status nginx --no-pager
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### Apache status on VM-2

From the administration terminal:

``` bash
az vm run-command invoke \
  -g "$RG" -n "$VM_BACKEND" \
  --command-id RunShellScript \
  --scripts "systemctl status apache2 --no-pager; ss -lntp | grep ':80'"
```

### Confirm backend has no public IP

``` bash
az vm show -d -g "$RG" -n "$VM_BACKEND" \
  --query "{privateIps:privateIps,publicIps:publicIps}" -o json
```

Expected: a private IP is populated and `publicIps` is empty.

------------------------------------------------------------------------

## 14. Optional: Route multiple web applications by URL path

Nginx can route different URL paths to different backend services. The
following is a future extension; this lab deploys only one backend VM.

``` nginx
location /app1/ {
    proxy_pass http://10.70.2.4:80/;
}

location /app2/ {
    proxy_pass http://10.70.2.5:80/;
}
```

Do not use the `10.70.2.5` example unless a second backend is actually
deployed and secured. The trailing slash in `proxy_pass` affects URI
rewriting; test path behavior with the application before production.

------------------------------------------------------------------------

## 15. Troubleshooting

  -----------------------------------------------------------------------
  Problem                             Checks
  ----------------------------------- -----------------------------------
  Browser cannot reach VM-1           Public IP, VM state, NSG TCP
                                      80/443, Nginx status

  SSH cannot reach VM-1               Admin CIDR, NSG TCP 22, SSH key

  Nginx returns 502                   Backend IP, Apache status, backend
                                      NSG, private connectivity

  Authentication prompt missing       Active Nginx site, `auth_basic` in
                                      correct location

  Authentication fails                Username/password, htpasswd path
                                      and permissions

  Backend is publicly exposed         Remove public IP; inspect backend
                                      NSG and NIC configuration

  HTTPS certificate fails             DNS record, port 80 reachability,
                                      domain ownership, Certbot logs

  Client IP is wrong in application   Forwarded headers and trusted-proxy
                                      configuration

  Nginx config error                  `sudo nginx -t`, then inspect error
                                      output
  -----------------------------------------------------------------------

Useful commands:

``` bash
sudo nginx -t
sudo systemctl status nginx --no-pager
sudo journalctl -u nginx -n 100 --no-pager
sudo tail -n 100 /var/log/nginx/error.log
curl -I "http://BACKEND_PRIVATE_IP"
```

------------------------------------------------------------------------

## 16. Production hardening checklist

-   Use HTTPS with a trusted certificate. Never expose Basic
    Authentication over plain HTTP.
-   Prefer Microsoft Entra ID/OIDC, SSO, or an identity-aware access
    layer over shared Basic Auth accounts for enterprise access.
-   Keep backend VMs private and without public IPs.
-   Permit backend ports only from the proxy subnet or specific proxy
    NIC addresses.
-   Restrict SSH to an approved management path; prefer Azure Bastion or
    private management access.
-   Patch Ubuntu and Nginx regularly.
-   Use least-privilege permissions for password files and certificates.
-   Configure applications to trust forwarded headers only from the
    proxy. Do not blindly trust client-supplied `X-Forwarded-For`.
-   Set appropriate request size limits, timeouts, rate limits, and
    security headers.
-   Enable access/error log collection, monitoring, alerts, and
    retention.
-   Protect certificates and secrets; monitor certificate expiry and
    renewal.
-   Use multiple Nginx instances behind Azure Load Balancer for Layer 4
    distribution or Application Gateway for managed Layer 7 routing and
    WAF capabilities.
-   Add health probes and test backend/proxy failure behavior.
-   Plan backups, recovery, capacity, and operational ownership.

### Single VM versus production availability

  -----------------------------------------------------------------------
  Design                              Availability
  ----------------------------------- -----------------------------------
  One Nginx VM                        Single point of failure

  Multiple Nginx VMs behind Azure     Better proxy-layer availability
  Load Balancer                       

  Azure Application Gateway with WAF  Managed Layer 7 entry point with
                                      WAF capabilities
  -----------------------------------------------------------------------

------------------------------------------------------------------------

## 17. Cleanup

Delete the resource group to remove both VMs, disks, public IP, VNet,
subnets, and NSGs:

``` bash
az group delete --name "$RG" --yes --no-wait
```

Verify:

``` bash
az group exists --name "$RG"
```

Expected after deletion completes:

``` text
false
```

------------------------------------------------------------------------

## 18. Teaching summary

**What is a reverse proxy?**\
A server that receives client requests, forwards them to backend
servers, and returns backend responses to the client.

**Why use Nginx?**\
It supports HTTP routing, TLS termination, authentication integration,
header handling, caching, rate limiting, and load balancing.

**Why does VM-2 have no public IP?**\
Only the reverse proxy should be publicly reachable. The backend is
accessed through private networking and restricted NSG rules.

**Does Nginx reverse proxy require IP forwarding?**\
No. Nginx terminates the client connection and creates a separate
connection to the backend. It is not forwarding the original IP packet
like a router.

**Does Basic Authentication encrypt credentials?**\
No. It must be used over HTTPS to protect credentials in transit.

**Final takeaway:** VM-1 is the public Layer 7 entry point. Nginx can
authenticate and proxy requests to VM-2 over its private IP, while VM-2
remains isolated from direct internet access.
