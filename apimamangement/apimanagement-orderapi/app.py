from flask import Flask, request, jsonify, render_template_string
from datetime import datetime

app = Flask(__name__)


# ============================================================
# DEMO ORDER DATA
# ============================================================

orders = {
    "1001": {
        "id": "1001",
        "customer": "Ashutosh",
        "product": "Laptop",
        "quantity": 1,
        "price": 75000,
        "status": "CREATED",
        "createdAt": "2026-08-12T10:30:00"
    },

    "1002": {
        "id": "1002",
        "customer": "Rahul",
        "product": "Phone",
        "quantity": 2,
        "price": 50000,
        "status": "CONFIRMED",
        "createdAt": "2026-08-12T11:15:00"
    },

    "1003": {
        "id": "1003",
        "customer": "Priya",
        "product": "Monitor",
        "quantity": 2,
        "price": 30000,
        "status": "SHIPPED",
        "createdAt": "2026-08-12T12:00:00"
    }
}


# ============================================================
# COMMON API RESPONSE
# ============================================================

def api_response(data, status_code=200):

    response = jsonify(data)

    response.status_code = status_code

    # Useful headers for Azure API Management demo
    response.headers["X-Backend-Service"] = "Azure-VM-Order-API"
    response.headers["X-API-Version"] = "v1"

    return response


# ============================================================
# DASHBOARD
# ============================================================

@app.route("/", methods=["GET"])
def dashboard():

    total_orders = len(orders)

    total_value = sum(
        order["price"] * order["quantity"]
        for order in orders.values()
    )

    confirmed = sum(
        1
        for order in orders.values()
        if order["status"] == "CONFIRMED"
    )

    shipped = sum(
        1
        for order in orders.values()
        if order["status"] == "SHIPPED"
    )

    created = sum(
        1
        for order in orders.values()
        if order["status"] == "CREATED"
    )

    html = """
<!DOCTYPE html>

<html>

<head>

<title>Azure Order Management API</title>

<meta name="viewport"
      content="width=device-width, initial-scale=1">

<style>

* {
    box-sizing: border-box;
}

body {

    margin: 0;

    font-family:
        Arial,
        Helvetica,
        sans-serif;

    background:
        linear-gradient(
            135deg,
            #eef4ff,
            #f8fbff
        );

    color: #1f2937;
}


/* =========================================================
   HEADER
   ========================================================= */

.header {

    background:
        linear-gradient(
            135deg,
            #0078d4,
            #005a9e
        );

    color: white;

    padding: 35px 50px;

}


.header h1 {

    margin: 0;

    font-size: 32px;

}


.header p {

    margin-top: 10px;

    opacity: 0.9;

    font-size: 16px;

}


/* =========================================================
   BADGES
   ========================================================= */

.badge {

    display: inline-block;

    background:
        rgba(255,255,255,0.18);

    color: white;

    padding: 7px 13px;

    border-radius: 20px;

    font-size: 13px;

    margin-top: 12px;

    margin-right: 5px;

}


/* =========================================================
   MAIN CONTAINER
   ========================================================= */

.container {

    max-width: 1200px;

    margin: 35px auto;

    padding: 0 25px;

}


/* =========================================================
   STAT CARDS
   ========================================================= */

.cards {

    display: grid;

    grid-template-columns:
        repeat(
            auto-fit,
            minmax(200px, 1fr)
        );

    gap: 20px;

    margin-bottom: 30px;

}


.card {

    background: white;

    border-radius: 15px;

    padding: 25px;

    box-shadow:
        0 8px 25px
        rgba(0,0,0,0.08);

}


.card h3 {

    margin: 0;

    color: #6b7280;

    font-size: 14px;

    text-transform: uppercase;

}


.number {

    font-size: 32px;

    font-weight: bold;

    margin-top: 10px;

    color: #0078d4;

}


/* =========================================================
   ORDER TABLE
   ========================================================= */

.section {

    background: white;

    border-radius: 15px;

    padding: 25px;

    box-shadow:
        0 8px 25px
        rgba(0,0,0,0.08);

}


.section h2 {

    margin-top: 0;

}


table {

    width: 100%;

    border-collapse: collapse;

}


th {

    background: #f1f5f9;

    text-align: left;

    padding: 14px;

    font-size: 14px;

}


td {

    padding: 14px;

    border-bottom:
        1px solid #e5e7eb;

}


tr:hover {

    background: #f8fafc;

}


/* =========================================================
   STATUS
   ========================================================= */

.status {

    padding: 6px 12px;

    border-radius: 20px;

    font-size: 12px;

    font-weight: bold;

}


.CREATED {

    background: #dbeafe;

    color: #1d4ed8;

}


.CONFIRMED {

    background: #dcfce7;

    color: #15803d;

}


.SHIPPED {

    background: #fef3c7;

    color: #b45309;

}


/* =========================================================
   FOOTER
   ========================================================= */

.footer {

    text-align: center;

    margin-top: 30px;

    margin-bottom: 30px;

    color: #6b7280;

    font-size: 14px;

}


/* =========================================================
   RESPONSIVE
   ========================================================= */

@media (max-width: 700px) {

    .header {

        padding: 25px;

    }

    .header h1 {

        font-size: 24px;

    }

    table {

        font-size: 12px;

    }

    th,
    td {

        padding: 9px;

    }

}

</style>

</head>


<body>


<!-- =======================================================
     HEADER
     ======================================================= -->

<div class="header">

    <h1>
        Azure Order Management API
    </h1>

    <p>
        Real-world REST API running on Azure Virtual Machine
    </p>


    <span class="badge">
        Flask
    </span>

    <span class="badge">
        Azure VM
    </span>

    <span class="badge">
        REST API
    </span>

    <span class="badge">
        APIM Ready
    </span>

</div>


<!-- =======================================================
     CONTENT
     ======================================================= -->

<div class="container">


<!-- =======================================================
     STATISTICS
     ======================================================= -->

<div class="cards">


<div class="card">

    <h3>
        Total Orders
    </h3>

    <div class="number">
        {{ total_orders }}
    </div>

</div>


<div class="card">

    <h3>
        Total Order Value
    </h3>

    <div class="number">
        ₹{{ "{:,}".format(total_value) }}
    </div>

</div>


<div class="card">

    <h3>
        Created
    </h3>

    <div class="number">
        {{ created }}
    </div>

</div>


<div class="card">

    <h3>
        Confirmed
    </h3>

    <div class="number">
        {{ confirmed }}
    </div>

</div>


<div class="card">

    <h3>
        Shipped
    </h3>

    <div class="number">
        {{ shipped }}
    </div>

</div>


</div>


<!-- =======================================================
     ORDER TABLE
     ======================================================= -->

<div class="section">

<h2>
    Order Management
</h2>


<table>

<thead>

<tr>

<th>
    Order ID
</th>

<th>
    Customer
</th>

<th>
    Product
</th>

<th>
    Quantity
</th>

<th>
    Price
</th>

<th>
    Status
</th>

</tr>

</thead>


<tbody>

{% for order in orders.values() %}

<tr>

<td>

<strong>
#{{ order.id }}
</strong>

</td>


<td>

{{ order.customer }}

</td>


<td>

{{ order.product }}

</td>


<td>

{{ order.quantity }}

</td>


<td>

₹{{ "{:,}".format(order.price) }}

</td>


<td>

<span class="status {{ order.status }}">

{{ order.status }}

</span>

</td>

</tr>

{% endfor %}

</tbody>

</table>

</div>


<!-- =======================================================
     FOOTER
     ======================================================= -->

<div class="footer">

    Azure VM
    →
    Flask Order API
    →
    Azure API Management

    <br><br>

    Backend Service:
    <strong>
        Azure-VM-Order-API
    </strong>

</div>


</div>


</body>

</html>
"""

    return render_template_string(
        html,
        orders=orders,
        total_orders=total_orders,
        total_value=total_value,
        created=created,
        confirmed=confirmed,
        shipped=shipped
    )


# ============================================================
# API DOCUMENTATION
# ============================================================

@app.route("/api-docs", methods=["GET"])
def api_docs():

    return """
<!DOCTYPE html>

<html>

<head>

<title>Order API Documentation</title>

<style>

body {

    font-family: Arial, sans-serif;

    background: #f4f7fb;

    margin: 0;

    padding: 40px;

}


.container {

    max-width: 950px;

    margin: auto;

    background: white;

    padding: 35px;

    border-radius: 15px;

    box-shadow:
        0 5px 25px
        rgba(0,0,0,.08);

}


h1 {

    color: #0078d4;

}


.subtitle {

    color: #6b7280;

    margin-bottom: 30px;

}


.endpoint {

    padding: 18px;

    margin: 14px 0;

    border-radius: 10px;

    background: #f8fafc;

    border-left:
        5px solid #0078d4;

}


.method {

    display: inline-block;

    font-weight: bold;

    color: #0078d4;

    width: 70px;

}


code {

    background: #eef2ff;

    padding: 4px 8px;

    border-radius: 5px;

}

</style>

</head>


<body>


<div class="container">


<h1>
    Order Management API
</h1>


<div class="subtitle">

    REST API hosted on Azure Virtual Machine

</div>


<div class="endpoint">

<span class="method">
GET
</span>

<code>
/orders
</code>

<br><br>

List all orders.

</div>


<div class="endpoint">

<span class="method">
GET
</span>

<code>
/orders/{id}
</code>

<br><br>

Get a specific order.

</div>


<div class="endpoint">

<span class="method">
POST
</span>

<code>
/orders
</code>

<br><br>

Create a new order.

</div>


<div class="endpoint">

<span class="method">
PUT
</span>

<code>
/orders/{id}
</code>

<br><br>

Update an existing order.

</div>


<div class="endpoint">

<span class="method">
DELETE
</span>

<code>
/orders/{id}
</code>

<br><br>

Delete an order.

</div>


<div class="endpoint">

<span class="method">
GET
</span>

<code>
/health
</code>

<br><br>

Check backend health.

</div>


</div>

</body>

</html>
"""


# ============================================================
# GET ALL ORDERS
# ============================================================

@app.route("/orders", methods=["GET"])
def get_orders():

    return api_response({

        "success": True,

        "service": "Order Management API",

        "version": "v1",

        "server": "Azure VM",

        "count": len(orders),

        "orders": list(orders.values())

    })


# ============================================================
# GET SINGLE ORDER
# ============================================================

@app.route("/orders/<order_id>", methods=["GET"])
def get_order(order_id):

    order = orders.get(order_id)

    if not order:

        return api_response({

            "success": False,

            "error": "ORDER_NOT_FOUND",

            "message":
                f"Order {order_id} does not exist"

        }, 404)


    return api_response({

        "success": True,

        "order": order

    })


# ============================================================
# CREATE ORDER
# ============================================================

@app.route("/orders", methods=["POST"])
def create_order():

    data = request.get_json(silent=True)


    # --------------------------------------------------------
    # Validate JSON
    # --------------------------------------------------------

    if not data:

        return api_response({

            "success": False,

            "error": "INVALID_JSON",

            "message":
                "Request body must contain valid JSON"

        }, 400)


    # --------------------------------------------------------
    # Required fields
    # --------------------------------------------------------

    required = [

        "customer",

        "product",

        "quantity",

        "price"

    ]


    missing = [

        field

        for field in required

        if field not in data

    ]


    if missing:

        return api_response({

            "success": False,

            "error": "MISSING_FIELDS",

            "fields": missing

        }, 400)


    # --------------------------------------------------------
    # Generate sequential Order ID
    # --------------------------------------------------------

    if orders:

        order_id = str(
            max(
                int(order_id)
                for order_id in orders.keys()
            ) + 1
        )

    else:

        order_id = "1001"


    # --------------------------------------------------------
    # Create order
    # --------------------------------------------------------

    order = {

        "id": order_id,

        "customer": data["customer"],

        "product": data["product"],

        "quantity": data["quantity"],

        "price": data["price"],

        "status": "CREATED",

        "createdAt":
            datetime.utcnow().isoformat()

    }


    orders[order_id] = order


    # --------------------------------------------------------
    # Response
    # --------------------------------------------------------

    return api_response({

        "success": True,

        "message":
            "Order created successfully",

        "order": order

    }, 201)


# ============================================================
# UPDATE ORDER
# ============================================================

@app.route("/orders/<order_id>", methods=["PUT"])
def update_order(order_id):

    # --------------------------------------------------------
    # Check order
    # --------------------------------------------------------

    if order_id not in orders:

        return api_response({

            "success": False,

            "error": "ORDER_NOT_FOUND",

            "message":
                f"Order {order_id} does not exist"

        }, 404)


    # --------------------------------------------------------
    # Read JSON
    # --------------------------------------------------------

    data = request.get_json(silent=True)


    if not data:

        return api_response({

            "success": False,

            "error": "INVALID_JSON",

            "message":
                "Request body must contain valid JSON"

        }, 400)


    order = orders[order_id]


    # --------------------------------------------------------
    # Update fields
    # --------------------------------------------------------

    order["customer"] = data.get(

        "customer",

        order["customer"]

    )


    order["product"] = data.get(

        "product",

        order["product"]

    )


    order["quantity"] = data.get(

        "quantity",

        order["quantity"]

    )


    order["price"] = data.get(

        "price",

        order["price"]

    )


    order["status"] = data.get(

        "status",

        order["status"]

    )


    # --------------------------------------------------------
    # Response
    # --------------------------------------------------------

    return api_response({

        "success": True,

        "message":
            "Order updated successfully",

        "order": order

    })


# ============================================================
# DELETE ORDER
# ============================================================

@app.route("/orders/<order_id>", methods=["DELETE"])
def delete_order(order_id):

    # --------------------------------------------------------
    # Check order
    # --------------------------------------------------------

    if order_id not in orders:

        return api_response({

            "success": False,

            "error": "ORDER_NOT_FOUND",

            "message":
                f"Order {order_id} does not exist"

        }, 404)


    # --------------------------------------------------------
    # Delete
    # --------------------------------------------------------

    deleted = orders.pop(order_id)


    # --------------------------------------------------------
    # Response
    # --------------------------------------------------------

    return api_response({

        "success": True,

        "message":
            "Order deleted successfully",

        "order": deleted

    })


# ============================================================
# HEALTH CHECK
# ============================================================

@app.route("/health", methods=["GET"])
def health():

    return api_response({

        "status": "UP",

        "service": "order-api",

        "version": "v1",

        "environment": "Azure VM",

        "timestamp":
            datetime.utcnow().isoformat()

    })


# ============================================================
# APPLICATION INFORMATION
# ============================================================

@app.route("/info", methods=["GET"])
def info():

    return api_response({

        "application":
            "Azure Order Management API",

        "version":
            "1.0",

        "environment":
            "Azure VM",

        "framework":
            "Flask",

        "apiVersion":
            "v1",

        "description":
            "Demo order management REST API",

        "endpoints": {

            "dashboard":
                "/",

            "documentation":
                "/api-docs",

            "health":
                "/health",

            "orders":
                "/orders"

        }

    })


# ============================================================
# ERROR HANDLERS
# ============================================================

@app.errorhandler(404)
def not_found(error):

    return api_response({

        "success": False,

        "error": "ENDPOINT_NOT_FOUND",

        "message":
            "The requested endpoint does not exist"

    }, 404)


@app.errorhandler(405)
def method_not_allowed(error):

    return api_response({

        "success": False,

        "error": "METHOD_NOT_ALLOWED",

        "message":
            "HTTP method is not supported for this endpoint"

    }, 405)


# ============================================================
# START APPLICATION
# ============================================================

if __name__ == "__main__":

    print("")
    print("==============================================")
    print("       AZURE ORDER MANAGEMENT API")
    print("==============================================")
    print("")
    print("Dashboard:")
    print("http://0.0.0.0:5000/")
    print("")
    print("API:")
    print("http://0.0.0.0:5000/orders")
    print("")
    print("API Documentation:")
    print("http://0.0.0.0:5000/api-docs")
    print("")
    print("Health:")
    print("http://0.0.0.0:5000/health")
    print("")
    print("Info:")
    print("http://0.0.0.0:5000/info")
    print("")
    print("==============================================")

    app.run(
        host="0.0.0.0",
        port=5000,
        debug=False
    )
