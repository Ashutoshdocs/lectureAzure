<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Azure Load Balancer Demo - VM2</title>

<style>
body{
margin:0;
font-family:Segoe UI,Arial;
background:linear-gradient(135deg,#134E5E,#71B280);
color:white;
}

.header{
background:#0a8f08;
padding:25px;
text-align:center;
font-size:40px;
font-weight:bold;
}

.container{
width:85%;
margin:auto;
padding:30px;
}

.card{
background:white;
color:#333;
border-radius:15px;
padding:30px;
margin-top:25px;
box-shadow:0 0 20px rgba(0,0,0,.4);
}

.vm{
font-size:55px;
font-weight:bold;
text-align:center;
color:#0a8f08;
}

h2{
color:#0a8f08;
}

.footer{
margin-top:40px;
background:#0a8f08;
padding:20px;
text-align:center;
}
</style>

</head>

<body>

<div class="header">
Microsoft Azure Load Balancer Demonstration
</div>

<div class="container">

<div class="card">

<div class="vm">
YOU ARE CONNECTED TO<br>
AZURE VM 02
</div>

<hr>

<h2>Azure Load Balancer Practical Demonstration</h2>

<p>
Congratulations. Your request has reached Azure Virtual Machine 02. This confirms that Azure Load Balancer is successfully distributing client traffic among multiple backend virtual machines.
</p>

<p>
Azure Standard Load Balancer provides high availability by routing network traffic only to healthy backend instances. Health probes periodically check application availability, ensuring uninterrupted service even if one virtual machine becomes unavailable.
</p>

<p>
Azure Load Balancer supports both inbound and outbound connectivity. Organizations commonly deploy it in front of Web Servers, API Servers, Kubernetes Nodes, Database Gateways, and enterprise applications requiring scalability and resilience.
</p>

<p>
Every browser refresh establishes a new TCP connection. Depending on Azure's hashing algorithm and session persistence settings, subsequent requests may arrive at a different backend server.
</p>

<p>
This architecture eliminates single points of failure while providing seamless scaling. Administrators can increase backend capacity simply by adding more virtual machines into the Backend Pool.
</p>

<p>
During Azure certification training, this demonstration clearly illustrates:
</p>

<ul>
<li>Backend Pool</li>
<li>Frontend Public IP</li>
<li>Health Probe</li>
<li>Load Balancing Rule</li>
<li>High Availability</li>
<li>Fault Tolerance</li>
<li>Traffic Distribution</li>
</ul>

<p>
If VM01 becomes unhealthy, Azure automatically redirects all future requests to this server without requiring users to change the public IP address.
</p>

<h2>Current Backend</h2>

<h1 style="color:#0a8f08;text-align:center;">
AZURE VM 02
</h1>

</div>

</div>

<div class="footer">
Azure Load Balancer Demo • Backend Server VM02
</div>

</body>
</html>
