Azure Front Door + NGINX Multi-Region Deployment Practical
Step-by-step practical for deploying multi-region NGINX virtual machines and configuring Azure Front Door for load balancing and failover.
Commands

# LOGIN
az login

# SET SUBSCRIPTION
az account set --subscription "<SUBSCRIPTION-ID>"

# RESOURCE GROUP
az group create --name cdn-waf-rg --location centralindia

# VM1 WEST US
az vm create --resource-group cdn-waf-rg --name westus-vm --image Ubuntu2204 --size Standard_B1s --admin-username azureuser --admin-password "warrison@123" --authentication-type password --location westus

# OPEN PORT 80 VM1
az vm open-port --resource-group cdn-waf-rg --name westus-vm --port 80

# INSTALL NGINX VM1
az vm run-command invoke --resource-group cdn-waf-rg --name westus-vm --command-id RunShellScript --scripts "sudo apt update && sudo apt install nginx -y && echo '<h1>Welcome From West US VM</h1>' | sudo tee /var/www/html/index.html && sudo systemctl restart nginx"

# VM2 CENTRAL US
az vm create --resource-group cdn-waf-rg --name centralus-vm --image Ubuntu2204 --size Standard_B1s --admin-username azureuser --admin-password "warrison@123" --authentication-type password --location centralus

# OPEN PORT 80 VM2
az vm open-port --resource-group cdn-waf-rg --name centralus-vm --port 80

# INSTALL NGINX VM2
az vm run-command invoke --resource-group cdn-waf-rg --name centralus-vm --command-id RunShellScript --scripts "sudo apt update && sudo apt install nginx -y && echo '<h1>Welcome From Central US VM</h1>' | sudo tee /var/www/html/index.html && sudo systemctl restart nginx"

# GET VM1 IP
$VM1IP=$(az vm show -d --resource-group cdn-waf-rg --name westus-vm --query publicIps -o tsv)

# GET VM2 IP
$VM2IP=$(az vm show -d --resource-group cdn-waf-rg --name centralus-vm --query publicIps -o tsv)

# CREATE FRONT DOOR
az afd profile create --resource-group cdn-waf-rg --profile-name my-frontdoor --sku Standard_AzureFrontDoor

# CREATE ENDPOINT
az afd endpoint create --resource-group cdn-waf-rg --profile-name my-frontdoor --endpoint-name my-nginx-endpoint --enabled-state Enabled

# CREATE ORIGIN GROUP
az afd origin-group create --resource-group cdn-waf-rg --profile-name my-frontdoor --origin-group-name nginx-origin-group --probe-request-type GET --probe-protocol Http --probe-interval-in-seconds 30 --probe-path "/" --sample-size 4 --successful-samples-required 3

# ADD VM1 AND VM2 TO ORIGIN GROUP
az afd origin create --resource-group cdn-waf-rg --profile-name my-frontdoor --origin-group-name nginx-origin-group --origin-name origin-eastus --host-name 104.42.123.74 --origin-host-header 104.42.123.74 --http-port 80 --enabled-state Enabled --priority 1 --weight 500

az afd origin create --resource-group cdn-waf-rg --profile-name my-frontdoor --origin-group-name nginx-origin-group --origin-name origin-westeurope --host-name 172.173.115.183 --origin-host-header 172.173.115.183 --http-port 80 --enabled-state Enabled --priority 1 --weight 500

# CREATE ROUTING RULE
az afd route create --resource-group cdn-waf-rg --profile-name my-frontdoor --endpoint-name my-nginx-endpoint --route-name nginx-route --origin-group nginx-origin-group --supported-protocols Http Https --patterns-to-match "/*" --forwarding-protocol HttpOnly --https-redirect Disabled --link-to-default-domain Enabled

#
az afd origin update --resource-group cdn-waf-rg  --profile-name my-frontdoor --origin-group-name nginx-origin-group --origin-name origin-westeurope --enforce-certificate-name-check false

#
az afd origin update --resource-group cdn-waf-rg  --profile-name my-frontdoor  --origin-group-name nginx-origin-group --origin-name origin-eastus --enforce-certificate-name-check false


# GET FRONT DOOR HOSTNAME
az afd endpoint show --resource-group cdn-waf-rg --profile-name my-frontdoor --endpoint-name my-nginx-endpoint --query hostName -o tsv

# CHECK STATUS
az afd endpoint show --resource-group cdn-waf-rg --profile-name my-frontdoor --endpoint-name my-nginx-endpoint --query deploymentStatus -o tsv

az afd route show --resource-group cdn-waf-rg --profile-name my-frontdoor --endpoint-name my-nginx-endpoint --route-name nginx-route --query deploymentStatus -o tsv

az afd origin-group show --resource-group cdn-waf-rg --profile-name my-frontdoor --origin-group-name nginx-origin-group --query deploymentStatus -o tsv

# UPDATE HEALTH PROBE
az afd origin-group update --resource-group cdn-waf-rg --profile-name my-frontdoor --origin-group-name nginx-origin-group --probe-interval-in-seconds 60

# DELETE ROUTE
az afd route delete --resource-group cdn-waf-rg --profile-name my-frontdoor --endpoint-name my-nginx-endpoint --route-name nginx-route

# RECREATE ROUTE
az afd route create --resource-group cdn-waf-rg --profile-name my-frontdoor --endpoint-name my-nginx-endpoint --route-name nginx-route --origin-group nginx-origin-group --supported-protocols Http Https --patterns-to-match "/*" --forwarding-protocol HttpOnly --https-redirect Disabled --link-to-default-domain Enabled

# LIST ORIGINS
az afd origin list --resource-group cdn-waf-rg --profile-name my-frontdoor --origin-group-name nginx-origin-group -o table

