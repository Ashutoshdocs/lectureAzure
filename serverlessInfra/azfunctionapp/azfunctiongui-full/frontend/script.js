// Paste YOUR function's Invoke URL here.
// Yours (from the last deploy) is:
const api = "https://myfunctionblaze-a9cva5dzeah7gvdw.centralus-01.azurewebsites.net/api/visitorcounter";

async function loadData() {
    const statusEl = document.getElementById("status");
    statusEl.innerHTML = "Loading...";
    statusEl.style.color = "green";

    try {
        const response = await fetch(api);

        if (!response.ok) {
            throw new Error("HTTP " + response.status);
        }

        const data = await response.json();

        document.getElementById("counter").innerHTML = data.visitors;
        document.getElementById("ip").innerHTML = data.ip;

        statusEl.innerHTML = "Connected Successfully";
        statusEl.style.color = "green";
    } catch (err) {
        // If it hangs on "Loading..." this now shows the real reason instead.
        document.getElementById("counter").innerHTML = "—";
        document.getElementById("ip").innerHTML = "—";
        statusEl.innerHTML = "Error: " + err.message;
        statusEl.style.color = "red";
        console.error("loadData failed:", err);
    }
}

loadData();
