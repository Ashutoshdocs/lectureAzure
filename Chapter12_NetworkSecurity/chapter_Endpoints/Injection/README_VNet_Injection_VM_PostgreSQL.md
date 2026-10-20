# Azure VNet Injection Demo — Azure VM → PostgreSQL Flexible Server

## 🎯 Objective

This practical demonstrates **VNet Injection** using:

- Azure VNet
- Azure VM (Ubuntu)
- Azure Database for PostgreSQL Flexible Server
- PostgreSQL delegated subnet

The goal is to prove that:

1. PostgreSQL is deployed using a **delegated subnet** in the VNet.
2. The PostgreSQL hostname resolves to a **private IP address**.
3. The Azure VM can communicate with PostgreSQL using the private network.
4. The PostgreSQL server has **no public endpoint** for Internet access.
5. Data can be inserted into PostgreSQL and queried from the Azure VM.

---

# 🏗️ Architecture

```text
                         AZURE
        ┌─────────────────────────────────────────┐
        │             VNet 10.0.0.0/16            │
        │                                         │
        │  VM Subnet              PostgreSQL     │
        │  10.0.1.0/24            Subnet         │
        │                          10.0.2.0/24   │
        │                                         │
        │  ┌──────────────┐      ┌─────────────┐ │
        │  │ Azure VM     │      │ PostgreSQL  │ │
        │  │ Ubuntu       │─────▶│ Flexible    │ │
        │  │ 10.0.1.x     │      │ Server      │ │
        │  └──────────────┘      │ 10.0.2.x    │ │
        │                         └─────────────┘ │
        │                              ▲          │
        │                              │          │
        │                    VNet Injection       │
        │                    / Delegated Subnet   │
        └─────────────────────────────────────────┘
```

## 🔑 Key Concept

**VNet Injection** means the supported Azure service is deployed into a subnet of your VNet.

In this demo:

```text
VNet
│
├── VM subnet
│   └── Azure VM
│
└── PostgreSQL delegated subnet
    └── PostgreSQL Flexible Server
```

The database connection from the VM uses the private VNet network.

---

# 1. Prerequisites

You need:

- Azure subscription
- Azure CLI
- PowerShell
- SSH client
- Permission to create Azure resources

Login:

```powershell
az login
```

Set the subscription if required:

```powershell
az account set --subscription "<SUBSCRIPTION_ID_OR_NAME>"
```

---

# 2. Set Variables

Run this in PowerShell:

```powershell
$LOCATION="centralindia"
$RG="VNetInjectionDemoRG"
$VNET="vnet-injection-demo"
$VM="client-vm"
$PG="pgvnetdemo$(Get-Random -Minimum 10000 -Maximum 99999)"
$ADMIN="pgadmin"
$PASSWORD="P@ssw0rd123456!"
```

> For a real environment, do not place production passwords directly in shell history or scripts. Use a secure secret-management solution.

---

# 3. Create Resource Group

```powershell
az group create `
  --name $RG `
  --location $LOCATION
```

Verify:

```powershell
az group show -n $RG -o table
```

---

# 4. Create VNet

Create the VNet with `10.0.0.0/16`:

```powershell
az network vnet create `
  --resource-group $RG `
  --name $VNET `
  --location $LOCATION `
  --address-prefix 10.0.0.0/16
```

Verify:

```powershell
az network vnet show `
  --resource-group $RG `
  --name $VNET `
  --query addressSpace.addressPrefixes
```

Expected:

```text
10.0.0.0/16
```

---

# 5. Create VM Subnet

```powershell
az network vnet subnet create `
  --resource-group $RG `
  --vnet-name $VNET `
  --name vm-subnet `
  --address-prefix 10.0.1.0/24
```

---

# 6. Create PostgreSQL Delegated Subnet

This is an important step.

```powershell
az network vnet subnet create `
  --resource-group $RG `
  --vnet-name $VNET `
  --name postgres-subnet `
  --address-prefix 10.0.2.0/24 `
  --delegations Microsoft.DBforPostgreSQL/flexibleServers
```

Verify the delegation:

```powershell
az network vnet subnet show `
  --resource-group $RG `
  --vnet-name $VNET `
  --name postgres-subnet `
  --query "{Name:name,Prefix:addressPrefix,Delegation:delegations[0].serviceName}"
```

Expected:

```text
Name        : postgres-subnet
Prefix      : 10.0.2.0/24
Delegation  : Microsoft.DBforPostgreSQL/flexibleServers
```

---

# 7. Create Azure VM

Create an Ubuntu VM inside the same VNet:

```powershell
az vm create `
  --resource-group $RG `
  --name $VM `
  --location $LOCATION `
  --image Ubuntu2404 `
  --vnet-name $VNET `
  --subnet vm-subnet `
  --admin-username azureuser `
  --generate-ssh-keys
```

Get the VM public IP:

```powershell
az vm show -d `
  --resource-group $RG `
  --name $VM `
  --query publicIps `
  -o tsv
```

Save the returned IP.

Example:

```text
20.x.x.x
```

SSH into the VM:

```powershell
ssh azureuser@<VM_PUBLIC_IP>
```

---

# 8. Create PostgreSQL Flexible Server with VNet Injection

Create the PostgreSQL server:

```powershell
az postgres flexible-server create `
  --resource-group $RG `
  --name $PG `
  --location $LOCATION `
  --vnet $VNET `
  --subnet postgres-subnet `
  --admin-user $ADMIN `
  --admin-password $PASSWORD `
  --sku-name Standard_B1ms `
  --tier Burstable `
  --storage-size 32 `
  --version 16
```

## ⭐ Important

These two parameters are the important part:

```text
--vnet $VNET
--subnet postgres-subnet
```

They tell Azure to deploy the PostgreSQL Flexible Server using the VNet and delegated subnet.

---

# 9. Get PostgreSQL FQDN

```powershell
az postgres flexible-server show `
  --resource-group $RG `
  --name $PG `
  --query fullyQualifiedDomainName `
  -o tsv
```

Save the result:

```text
<PG-FQDN>
```

Example:

```text
pgvnetdemo12345.postgres.database.azure.com
```

---

# 10. Verify PostgreSQL Networking

Run:

```powershell
az postgres flexible-server show `
  --resource-group $RG `
  --name $PG `
  --query "{Name:name,FQDN:fullyQualifiedDomainName,PublicNetworkAccess:network.publicNetworkAccess,DelegatedSubnet:network.delegatedSubnetResourceId}" `
  -o json
```

Also verify the subnet:

```powershell
az network vnet subnet show `
  --resource-group $RG `
  --vnet-name $VNET `
  --name postgres-subnet `
  --query "{Prefix:addressPrefix,Delegation:delegations[0].serviceName}" `
  -o json
```

---

# 11. Prove DNS Resolves to a Private IP

SSH into the Azure VM:

```powershell
ssh azureuser@<VM_PUBLIC_IP>
```

Install DNS utilities if necessary:

```bash
sudo apt update
sudo apt install dnsutils -y
```

Run:

```bash
nslookup <PG-FQDN>
```

Example:

```bash
nslookup pgvnetdemo12345.postgres.database.azure.com
```

Look at the returned address.

You want to see a private RFC1918 address such as:

```text
Address: 10.0.2.4
```

The important point is:

```text
10.0.2.4
```

is a private IP address.

---

# 12. Prove the VM Has a Route to the Private IP

Suppose PostgreSQL resolves to:

```text
10.0.2.4
```

Run:

```bash
ip route get 10.0.2.4
```

Example:

```text
10.0.2.4 dev eth0 src 10.0.1.4
```

This shows that the VM is sending traffic through its network interface toward the private destination.

---

# 13. Prove TCP 5432 Connectivity

Install netcat:

```bash
sudo apt install netcat-openbsd -y
```

Test PostgreSQL:

```bash
nc -vz 10.0.2.4 5432
```

Expected:

```text
Connection to 10.0.2.4 5432 port [tcp/postgresql] succeeded!
```

This proves TCP connectivity to PostgreSQL's private address.

---

# 14. Install PostgreSQL Client on VM

```bash
sudo apt update
sudo apt install postgresql-client -y
```

Verify:

```bash
psql --version
```

---

# 15. Connect to PostgreSQL from the VM

Use the PostgreSQL FQDN:

```bash
psql "host=<PG-FQDN> port=5432 dbname=postgres user=pgadmin sslmode=require"
```

Example:

```bash
psql "host=pgvnetdemo12345.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

Enter:

```text
P@ssw0rd123456!
```

Successful connection:

```text
postgres=#
```

---

# 16. ⭐ Create a Database

Inside `psql`:

```sql
CREATE DATABASE vnetdemo;
```

List databases:

```sql
\l
```

Connect:

```sql
\c vnetdemo
```

Expected:

```text
You are now connected to database "vnetdemo".
```

---

# 17. ⭐ Create a Table

Run:

```sql
CREATE TABLE students (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    course VARCHAR(100),
    city VARCHAR(100)
);
```

Verify:

```sql
\dt
```

Expected:

```text
students
```

---

# 18. ⭐ Insert Data

Run:

```sql
INSERT INTO students (name, course, city)
VALUES
('Rahul', 'Azure Networking', 'Pune'),
('Priya', 'Kubernetes', 'Mumbai'),
('Amit', 'Terraform', 'Delhi'),
('Neha', 'Azure DevOps', 'Bangalore');
```

Expected:

```text
INSERT 0 4
```

---

# 19. ⭐ Query Data from the Azure VM

This is the final application/data proof.

Run:

```sql
SELECT * FROM students;
```

Expected:

```text
 id | name  |       course        |   city
----+-------+---------------------+-----------
  1 | Rahul | Azure Networking    | Pune
  2 | Priya | Kubernetes          | Mumbai
  3 | Amit  | Terraform           | Delhi
  4 | Neha  | Azure DevOps        | Bangalore
```

You have now demonstrated:

```text
Azure VM
   │
   │ Private VNet connectivity
   ▼
PostgreSQL
   │
   ▼
Database
   │
   ▼
students table
   │
   ▼
SELECT * FROM students;
```

---

# 20. ⭐ Stronger Proof — Query Using Private IP

Once you know the PostgreSQL private IP:

```text
10.0.2.4
```

You can test connectivity:

```bash
nc -vz 10.0.2.4 5432
```

You can also connect directly using the private IP:

```bash
psql "host=10.0.2.4 port=5432 dbname=vnetdemo user=pgadmin sslmode=require"
```

Then:

```sql
SELECT * FROM students;
```

If your configuration permits direct private-IP connection and PostgreSQL TLS certificate validation is handled appropriately, this demonstrates the database is reachable at its private network address.

For normal application connections, prefer the PostgreSQL FQDN rather than hard-coding the private IP.

---

# 21. ⭐ Prove the Laptop Cannot Directly Reach the Private Database

The Azure VM has access to the VNet.

Your normal laptop on the Internet does not automatically have a route to:

```text
10.0.2.4
```

From your laptop, attempting:

```bash
nc -vz 10.0.2.4 5432
```

should not establish a connection unless your laptop has some separate private connectivity into the Azure VNet, such as VPN or ExpressRoute.

This demonstrates the difference:

```text
                         INTERNET
                            │
                            X
                            │
                    10.0.2.4:5432
                       PRIVATE IP
                            ▲
                            │
                     ┌──────┴──────┐
                     │ Azure VNet  │
                     │             │
                     │ Azure VM    │
                     └─────────────┘
```

---

# 22. Complete Proof Checklist

Run these commands from the Azure VM:

### Proof 1 — DNS

```bash
nslookup <PG-FQDN>
```

Expected:

```text
Private IP
10.x.x.x
```

### Proof 2 — Route

```bash
ip route get <PRIVATE_IP>
```

Expected:

```text
<PRIVATE_IP> dev eth0 src <VM_PRIVATE_IP>
```

### Proof 3 — TCP

```bash
nc -vz <PRIVATE_IP> 5432
```

Expected:

```text
succeeded
```

### Proof 4 — PostgreSQL

```bash
psql "host=<PG-FQDN> port=5432 dbname=vnetdemo user=pgadmin sslmode=require"
```

Expected:

```text
postgres=#
```

### Proof 5 — Actual data

```sql
SELECT * FROM students;
```

Expected:

```text
Rahul
Priya
Amit
Neha
```

---

# 23. The Final Teaching Diagram

```text
                         INTERNET
                            │
                            │
                    SSH to VM only
                            │
                            ▼
                 ┌──────────────────┐
                 │    Azure VM      │
                 │                  │
                 │ Private IP       │
                 │ 10.0.1.x         │
                 └────────┬─────────┘
                          │
                          │
                    PRIVATE VNET
                          │
                          │ TCP 5432
                          ▼
                 ┌──────────────────┐
                 │ PostgreSQL       │
                 │ Flexible Server  │
                 │                  │
                 │ Private IP       │
                 │ 10.0.2.x         │
                 └────────┬─────────┘
                          │
                          ▼
                    vnetdemo DB
                          │
                          ▼
                     students
                          │
                          ▼
                SELECT * FROM students;
```

## 🎓 One-line explanation

> **The VM is only publicly accessible for SSH; the VM-to-PostgreSQL communication uses PostgreSQL's private address inside the VNet, and the database data can be queried from the VM without using a public database endpoint.**

---

# 24. Cleanup

When the practical is finished:

```powershell
az group delete `
  --name $RG `
  --yes `
  --no-wait
```

This removes:

- Azure VM
- VNet
- Subnets
- PostgreSQL Flexible Server
- Associated resources
