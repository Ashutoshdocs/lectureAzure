<?php

$conn=new mysqli(
 getenv("DB_HOST"),
 getenv("DB_USER"),
 getenv("DB_PASSWORD"),
 getenv("DB_NAME")
);

if(isset($_POST['save']))
{
$name=$_POST['name'];
$msg=$_POST['message'];

$conn->query("INSERT INTO users(name,message)
VALUES('$name','$msg')");
}

$data=$conn->query("SELECT * FROM users ORDER BY id DESC");

?>

<!DOCTYPE html>
<html>
<head>

<title>AKS MySQL Demo</title>

<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">

</head>

<body class="bg-light">

<div class="container mt-5">

<div class="card shadow">

<div class="card-header bg-primary text-white">

<h2>AKS MySQL Demo</h2>

</div>

<div class="card-body">

<form method="post">

<input class="form-control mb-3"
name="name"
placeholder="Name">

<input class="form-control mb-3"
name="message"
placeholder="Message">

<button class="btn btn-success"
name="save">

Save

</button>

</form>

<hr>

<table class="table table-bordered">

<tr>

<th>ID</th>

<th>Name</th>

<th>Message</th>

</tr>

<?php

while($r=$data->fetch_assoc())
{

echo "<tr>

<td>".$r['id']."</td>

<td>".$r['name']."</td>

<td>".$r['message']."</td>

</tr>";

}

?>

</table>

</div>

</div>

</div>

</body>

</html>