"use strict";

const byId = id => document.getElementById(id);
const arena = byId("arena");
const server = byId("server");
const maps = byId("maps");
const result = byId("result");
const play = byId("play");
let arenaList = "";

function title(id) {
  return id.split("_").map(word => word.charAt(0).toUpperCase() + word.slice(1)).join(" ");
}

async function refresh() {
  try {
    const response = await fetch("/api/status", { cache: "no-store" });
    const data = await response.json();
    if (!data) throw new Error("Offline");
    arena.textContent = data.mode === "hold" ? data.title + " · Capture and hold" : data.title;
    server.textContent = data.name;
    byId("score").hidden = false;
    byId("lime").textContent = data.score[0];
    byId("blue").textContent = data.score[1];
    const seconds = Math.max(0, data.seconds);
    byId("time").textContent = data.over ? "Final" :
      String(Math.floor(seconds / 60)).padStart(2, "0") + ":" + String(seconds % 60).padStart(2, "0");
    byId("roster").textContent = `${data.players.length}/${data.slots} players · ${data.bots} bots`;
    byId("join").textContent = `Join from Android or Linux at ${location.hostname}, UDP port ${data.game_port}.`;
    const browserHost = location.hostname;
    const ws = data.ws_url || (location.protocol === "https:"
      ? `wss://${location.host}/match`
      : `ws://${browserHost}:${data.ws_port}`);
    play.href = "/play/?server=" + encodeURIComponent(ws);
    play.hidden = !data.browser;
    byId("admin").hidden = !data.admin;
    const nextList = data.maps.join(",");
    if (nextList !== arenaList) {
      maps.replaceChildren(...data.maps.map(id => new Option(title(id), id)));
      maps.value = data.map;
      arenaList = nextList;
    }
  } catch {
    arena.textContent = "Dedicated server";
    server.textContent = "Server offline";
    byId("score").hidden = true;
    byId("roster").textContent = "";
    byId("join").textContent = "";
    play.hidden = true;
    byId("admin").hidden = true;
  }
}

byId("round").addEventListener("submit", async event => {
  event.preventDefault();
  const button = event.currentTarget.querySelector("button");
  button.disabled = true;
  result.hidden = false;
  try {
    const password = byId("password");
    const credentials = new TextEncoder().encode("admin:" + password.value);
    const response = await fetch("/api/round", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Skifrei-Admin": "1",
        "Authorization": "Basic " + btoa(String.fromCharCode(...credentials)),
      },
      body: JSON.stringify({ map: maps.value }),
    });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || "Could not start a round.");
    result.textContent = "Starting " + title(maps.value) + "…";
    password.value = "";
  } catch (error) {
    result.textContent = error.message;
  } finally {
    button.disabled = false;
  }
});

refresh();
setInterval(refresh, 2500);
