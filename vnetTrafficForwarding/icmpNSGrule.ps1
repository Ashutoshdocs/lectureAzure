az network nsg rule create `
  --resource-group RG-AllowForwardDemo `
  --nsg-name VM-ANSG `
  --name Allow-ICMP `
  --priority 100 `
  --direction Inbound `
  --access Allow `
  --protocol Icmp `
  --source-address-prefixes "*" `
  --source-port-ranges "*" `
  --destination-address-prefixes "*" `
  --destination-port-ranges "*"



az network nsg rule create `
  --resource-group RG-AllowForwardDemo `
  --nsg-name VM-CNSG `
  --name Allow-ICMP `
  --priority 100 `
  --direction Inbound `
  --access Allow `
  --protocol Icmp `
  --source-address-prefixes "*" `
  --source-port-ranges "*" `
  --destination-address-prefixes "*" `
  --destination-port-ranges "*"