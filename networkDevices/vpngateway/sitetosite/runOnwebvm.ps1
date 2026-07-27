sudo apt update

sudo apt install nginx -y

echo "<h1>Azure Site to Site VPN Demo</h1>" | sudo tee /var/www/html/index.html

sudo systemctl restart nginx