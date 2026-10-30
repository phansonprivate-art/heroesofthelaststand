// Schickt Python-Code an Blender (offizielle MCP-Erweiterung, Port 9876) und gibt die Antwort aus.
const net = require("net");
const code = process.argv[2];
const s = net.connect(9876, "127.0.0.1");
let buf = "";
const done = () => { clearTimeout(t); try { const r = JSON.parse(buf.replace(/\0/g, "")); if (r.stdout) process.stdout.write(r.stdout); if (r.stderr) process.stderr.write(r.stderr); if (r.status !== "ok") console.log("STATUS", r.status, r.message || ""); } catch (e) { console.log(buf); } s.end(); process.exit(0); };
s.on("connect", () => s.write(JSON.stringify({type: "execute", code, strict_json: false}) + "\0"));
s.on("data", d => { buf += d; try { JSON.parse(buf.replace(/\0/g, "")); done(); } catch (e) {} });
s.on("error", e => { console.log("FEHLER " + e.message); process.exit(1); });
const t = setTimeout(() => { console.log("TIMEOUT " + buf); process.exit(2); }, 60000);
