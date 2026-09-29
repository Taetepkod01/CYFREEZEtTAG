import "reflect-metadata";
import path from "path";
import http from "http";
import express from "express";
import cors from "cors";
import { WebSocketServer, WebSocket } from "ws";
import { Server, matchMaker, WebSocketTransport } from "colyseus";
import { GameRoom } from "./rooms/GameRoom";

const PORT = Number(process.env.PORT) || 2567;
const clientBuildPath = path.join(__dirname, "../public");

const app = express();
app.use(cors());
app.use(express.json());

// COOP and COEP headers for Godot 4 WebAssembly / SharedArrayBuffer
app.use((_req, res, next) => {
  res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
  res.setHeader("Cross-Origin-Embedder-Policy", "require-corp");
  next();
});

// Health check endpoint for Render.com
app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    server: "CPFreezeTag-3D Server (Colyseus + WebSocket)",
    timestamp: Date.now()
  });
});

// ── Shared 3D Room Management for Godot Client-Server ───────────────────────
export interface ActivePlayer {
  id: string;
  name: string;
  ws: WebSocket;
  x: number;
  y: number;
  z: number;
  rotY: number;
  role: "tagger" | "runner";
  frozen: boolean;
  isRescuing: boolean;
  hasShield: boolean;
  speedMultiplier: number;
  heldItem: string;
  freezeCount: number;
  rescueCount: number;
}

export interface Active3DRoom {
  code: string;
  name: string;
  hostId: string;
  maxPlayers: number;
  rounds: number;
  currentRound: number;
  map: string;
  phase: "lobby" | "playing" | "ended";
  timeLeft: number;
  runnersScore: number;
  taggersScore: number;
  players: Map<string, ActivePlayer>;
  items: Map<string, { id: string; type: string; x: number; y: number; z: number }>;
  timerInterval: NodeJS.Timeout | null;
  itemSpawnInterval: NodeJS.Timeout | null;
  itemCounter: number;
}

const active3DRooms: Map<string, Active3DRoom> = new Map();

// Public rooms API for Godot Lobby Browser
app.get("/api/rooms", async (_req, res) => {
  const list: Array<{
    code: string;
    name: string;
    playersCount: number;
    maxPlayers: number;
    map: string;
    rounds: number;
    hasStarted: boolean;
  }> = [];

  active3DRooms.forEach((r) => {
    list.push({
      code: r.code,
      name: r.name,
      playersCount: r.players.size,
      maxPlayers: r.maxPlayers,
      map: r.map,
      rounds: r.rounds,
      hasStarted: r.phase !== "lobby"
    });
  });

  // Also query Colyseus rooms if any
  try {
    const colyseusRooms = await matchMaker.query({ name: "game_room" });
    colyseusRooms.forEach(cr => {
      const code = cr.metadata?.roomCode || cr.roomId;
      if (!active3DRooms.has(code)) {
        list.push({
          code: code,
          name: cr.metadata?.roomName || `Room ${code}`,
          playersCount: cr.clients,
          maxPlayers: cr.maxClients,
          map: cr.metadata?.map || "CASTLE",
          rounds: cr.metadata?.rounds || 3,
          hasStarted: cr.metadata?.hasStarted || false
        });
      }
    });
  } catch (_e) {}

  res.json(list);
});

// Serve static Godot Web Export (if built)
app.use(express.static(clientBuildPath));

app.use((req, res, next) => {
  if (req.method === "GET" && !req.path.startsWith("/colyseus") && !req.path.startsWith("/matchmake") && !req.path.startsWith("/api") && !req.path.startsWith("/ws")) {
    return res.sendFile(path.join(clientBuildPath, "index.html"), (err) => {
      if (err) {
        res.send(`
          <!DOCTYPE html>
          <html>
            <head>
              <title>CPFreezeTag 3D Server</title>
              <style>
                body { background: #0b1528; color: #64b5f6; font-family: sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; text-align: center; }
                .card { background: #040916; border: 2px solid #29b6f6; border-radius: 12px; padding: 40px; box-shadow: 0 8px 32px rgba(0,0,0,0.5); }
                h1 { color: #ffe066; margin-top: 0; }
                p { color: #e0f2fe; }
                .badge { display: inline-block; background: #0288d1; color: white; padding: 6px 16px; border-radius: 20px; font-weight: bold; }
              </style>
            </head>
            <body>
              <div class="card">
                <h1>❄️ CPFreezeTag-3D Server</h1>
                <p class="badge">ONLINE (Port ${PORT})</p>
                <p>WebSocket Endpoint: <code>ws://&lt;host&gt;:${PORT}/ws</code></p>
                <p>Full-Stack Client-to-Server Ready on Render.com</p>
              </div>
            </body>
          </html>
        `);
      }
    });
  }
  next();
});

const server = http.createServer(app);

// ── Colyseus GameServer Initialization (noServer: true to avoid upgrade collision) ──
const colyseusTransport = new WebSocketTransport({ noServer: true });
const gameServer = new Server({
  transport: colyseusTransport
});
gameServer.define("game_room", GameRoom);

// ── Direct High-Speed WebSocket Server for Godot 3D Client (/ws) ─────────────
const wss = new WebSocketServer({ noServer: true });

// Unified HTTP Upgrade dispatcher routing /ws to Godot and all other endpoints to Colyseus
server.on("upgrade", (request, socket, head) => {
  try {
    const host = request.headers.host || "localhost";
    const url = new URL(request.url || "", `http://${host}`);
    if (url.pathname === "/ws") {
      wss.handleUpgrade(request, socket, head, (ws) => {
        wss.emit("connection", ws, request);
      });
    } else {
      (colyseusTransport as any).wss.handleUpgrade(request, socket, head, (ws: any) => {
        (colyseusTransport as any).wss.emit("connection", ws, request);
      });
    }
  } catch (err) {
    console.error("[Server] Upgrade error:", err);
    socket.destroy();
  }
});

const CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
function generateCode(): string {
  return Array.from({ length: 6 }, () => CHARS[Math.floor(Math.random() * CHARS.length)]).join("");
}

const SPAWN_3D_POSITIONS = [
  { x: 0, y: 0.5, z: 0 },
  { x: -14, y: 0.5, z: -14 },
  { x: 14, y: 0.5, z: 14 },
  { x: 14, y: 0.5, z: -14 },
  { x: -14, y: 0.5, z: 14 },
  { x: 0, y: 0.5, z: 16 },
  { x: 0, y: 0.5, z: -16 },
  { x: 16, y: 0.5, z: 0 },
  { x: -16, y: 0.5, z: 0 }
];

function broadcastToRoom(room: Active3DRoom, event: string, data: unknown, excludeWs?: WebSocket) {
  const payload = JSON.stringify({ event, data });
  room.players.forEach(p => {
    if (p.ws !== excludeWs && p.ws.readyState === WebSocket.OPEN) {
      try { p.ws.send(payload); } catch (_e) {}
    }
  });
}

function sendTo(ws: WebSocket, event: string, data: unknown) {
  if (ws.readyState === WebSocket.OPEN) {
    try { ws.send(JSON.stringify({ event, data })); } catch (_e) {}
  }
}

wss.on("connection", (ws: WebSocket) => {
  let currentRoom: Active3DRoom | null = null;
  let myPlayerId = `p_${Math.random().toString(36).substring(2, 9)}`;

  ws.on("message", (rawMsg: Buffer | string) => {
    try {
      const msg = JSON.parse(rawMsg.toString());
      const action = msg.action || msg.type || "";

      switch (action) {
        // 1. Create Room (Host)
        case "create_room": {
          const code = generateCode();
          const rName = String(msg.roomName || `Room ${code}`);
          const pName = String(msg.playerName || "Host");
          const maxP = Math.max(4, Math.min(8, Number(msg.maxPlayers) || 8));
          const rounds = Math.max(1, Math.min(5, Number(msg.rounds) || 3));
          const map = String(msg.map || "CASTLE");

          const newRoom: Active3DRoom = {
            code,
            name: rName,
            hostId: myPlayerId,
            maxPlayers: maxP,
            rounds,
            currentRound: 1,
            map,
            phase: "lobby",
            timeLeft: 165,
            runnersScore: 0,
            taggersScore: 0,
            players: new Map(),
            items: new Map(),
            timerInterval: null,
            itemSpawnInterval: null,
            itemCounter: 0
          };

          const p: ActivePlayer = {
            id: myPlayerId,
            name: pName,
            ws,
            x: 0,
            y: 0.5,
            z: 0,
            rotY: 0,
            role: "runner",
            frozen: false,
            isRescuing: false,
            hasShield: false,
            speedMultiplier: 1.0,
            heldItem: "",
            freezeCount: 0,
            rescueCount: 0
          };

          newRoom.players.set(myPlayerId, p);
          active3DRooms.set(code, newRoom);
          currentRoom = newRoom;

          sendTo(ws, "room_created", {
            code,
            name: rName,
            myId: myPlayerId,
            isHost: true,
            maxPlayers: maxP,
            rounds,
            map,
            players: [{ id: p.id, name: p.name, isHost: true }]
          });
          console.log(`[WS Server] Room created: ${code} by ${pName}`);
          break;
        }

        // Get Public Rooms List
        case "get_rooms": {
          const list: Array<any> = [];
          active3DRooms.forEach((r) => {
            list.push({
              code: r.code,
              name: r.name,
              playersCount: r.players.size,
              maxPlayers: r.maxPlayers,
              map: r.map,
              rounds: r.rounds,
              hasStarted: r.phase !== "lobby"
            });
          });
          sendTo(ws, "public_rooms_updated", list);
          break;
        }

        // 2. Join Room by Code
        case "join_room": {
          const code = String(msg.roomCode || "").toUpperCase().trim();
          const pName = String(msg.playerName || "Player");

          const room = active3DRooms.get(code);
          if (!room) {
            sendTo(ws, "error", { message: `Room not found: "${code}"` });
            return;
          }
          if (room.phase !== "lobby") {
            sendTo(ws, "error", { message: `Match already in progress for room "${code}"` });
            return;
          }
          if (room.players.size >= room.maxPlayers) {
            sendTo(ws, "error", { message: `Room "${code}" is already full (${room.players.size}/${room.maxPlayers})` });
            return;
          }

          const sp = SPAWN_3D_POSITIONS[room.players.size % SPAWN_3D_POSITIONS.length];
          const newPlayer: ActivePlayer = {
            id: myPlayerId,
            name: pName,
            ws,
            x: sp.x,
            y: sp.y,
            z: sp.z,
            rotY: 0,
            role: "runner",
            frozen: false,
            isRescuing: false,
            hasShield: false,
            speedMultiplier: 1.0,
            heldItem: "",
            freezeCount: 0,
            rescueCount: 0
          };

          room.players.set(myPlayerId, newPlayer);
          currentRoom = room;

          const pList = Array.from(room.players.values()).map(pl => ({
            id: pl.id,
            name: pl.name,
            isHost: pl.id === room.hostId
          }));

          sendTo(ws, "room_joined", {
            code: room.code,
            name: room.name,
            myId: myPlayerId,
            isHost: myPlayerId === room.hostId,
            maxPlayers: room.maxPlayers,
            rounds: room.rounds,
            map: room.map,
            players: pList
          });

          broadcastToRoom(room, "player_joined", {
            id: newPlayer.id,
            name: newPlayer.name,
            isHost: false,
            playersCount: room.players.size,
            maxPlayers: room.maxPlayers
          }, ws);

          console.log(`[WS Server] ${pName} joined room ${code}`);
          break;
        }

        // 3. Update Settings (Host)
        case "update_settings": {
          if (!currentRoom || currentRoom.hostId !== myPlayerId) return;
          if (msg.maxPlayers) currentRoom.maxPlayers = Math.max(4, Math.min(8, Number(msg.maxPlayers)));
          if (msg.rounds) currentRoom.rounds = Math.max(1, Math.min(5, Number(msg.rounds)));
          if (msg.map) currentRoom.map = String(msg.map);

          broadcastToRoom(currentRoom, "settings_updated", {
            maxPlayers: currentRoom.maxPlayers,
            rounds: currentRoom.rounds,
            map: currentRoom.map
          });
          break;
        }

        // 4. Start Game (Host)
        case "start_game": {
          if (!currentRoom || currentRoom.hostId !== myPlayerId) return;
          start3DRound(currentRoom);
          break;
        }

        // 5. 3D Movement
        case "move": {
          if (!currentRoom || currentRoom.phase !== "playing") return;
          const p = currentRoom.players.get(myPlayerId);
          if (!p || p.frozen) return;

          p.x = Number(msg.x) || p.x;
          p.y = Number(msg.y) || p.y;
          p.z = Number(msg.z) || p.z;
          if (typeof msg.rotY === "number") p.rotY = msg.rotY;

          broadcastToRoom(currentRoom, "player_moved", {
            id: myPlayerId,
            x: p.x,
            y: p.y,
            z: p.z,
            rotY: p.rotY
          }, ws);
          break;
        }

        // 6. Tag Player
        case "tag_player": {
          if (!currentRoom || currentRoom.phase !== "playing") return;
          const tagger = currentRoom.players.get(myPlayerId);
          const victim = currentRoom.players.get(String(msg.victimId));
          if (!tagger || !victim || tagger.role !== "tagger" || victim.role !== "runner" || victim.frozen) return;

          if (victim.hasShield) {
            victim.hasShield = false;
            broadcastToRoom(currentRoom, "shield_broken", { playerId: victim.id });
            broadcastToRoom(currentRoom, "chat_message", { msg: `🛡️ ${victim.name}'s shield broke!` });
          } else {
            victim.frozen = true;
            victim.isRescuing = false;
            tagger.freezeCount += 1;
            broadcastToRoom(currentRoom, "player_tagged", {
              taggerId: tagger.id,
              taggerName: tagger.name,
              victimId: victim.id,
              victimName: victim.name
            });
            check3DEndCondition(currentRoom);
          }
          break;
        }

        // 7. Rescue Player
        case "rescue_player": {
          if (!currentRoom || currentRoom.phase !== "playing") return;
          const rescuer = currentRoom.players.get(myPlayerId);
          const victim = currentRoom.players.get(String(msg.victimId));
          if (!rescuer || !victim || rescuer.role !== "runner" || rescuer.frozen || !victim.frozen) return;

          victim.frozen = false;
          rescuer.rescueCount += 1;
          broadcastToRoom(currentRoom, "player_rescued", {
            rescuerId: rescuer.id,
            rescuerName: rescuer.name,
            victimId: victim.id,
            victimName: victim.name
          });
          break;
        }

        // 8. Rescuing proximity
        case "rescuing_state": {
          if (!currentRoom) return;
          const p = currentRoom.players.get(myPlayerId);
          if (p && !p.frozen && p.role === "runner") {
            p.isRescuing = Boolean(msg.isRescuing);
            broadcastToRoom(currentRoom, "player_rescuing", {
              playerId: p.id,
              isRescuing: p.isRescuing
            }, ws);
          }
          break;
        }

        // 9. Item Pick up
        case "pick_item": {
          if (!currentRoom || currentRoom.phase !== "playing") return;
          const p = currentRoom.players.get(myPlayerId);
          const itemId = String(msg.itemId);
          const item = currentRoom.items.get(itemId);
          if (!p || !item || p.heldItem !== "") return;
          if ((item.type === "heater" || item.type === "tackle") && p.role === "tagger") return;

          p.heldItem = item.type;
          currentRoom.items.delete(itemId);

          broadcastToRoom(currentRoom, "item_picked", {
            playerId: p.id,
            playerName: p.name,
            itemId,
            itemType: item.type
          });
          break;
        }

        // 10. Item Use
        case "use_item": {
          if (!currentRoom || currentRoom.phase !== "playing") return;
          const p = currentRoom.players.get(myPlayerId);
          if (!p || p.heldItem === "") return;

          const itemType = p.heldItem;
          p.heldItem = "";

          broadcastToRoom(currentRoom, "item_used", {
            playerId: p.id,
            playerName: p.name,
            type: itemType
          });

          if (itemType === "banana") {
            broadcastToRoom(currentRoom, "banana_placed", { x: p.x, y: p.y, z: p.z });
          } else if (itemType === "vortex") {
            // Teleport user to random location on map
            p.x = Math.round((Math.random() * 40 - 20) * 10) / 10;
            p.z = Math.round((Math.random() * 40 - 20) * 10) / 10;
            broadcastToRoom(currentRoom, "player_moved", { id: p.id, x: p.x, y: p.y, z: p.z, rotY: p.rotY });
            broadcastToRoom(currentRoom, "chat_message", { msg: `🌀 ${p.name} teleported across the arena!` });
          } else if (itemType === "tackle") {
            broadcastToRoom(currentRoom, "chat_message", { msg: `💥 ${p.name} dashed with a tackle attack!` });
          } else if (itemType === "heater") {
            if (p.frozen) {
              p.frozen = false;
              broadcastToRoom(currentRoom, "player_unfrozen", { playerId: p.id });
            }
          }
          break;
        }
      }
    } catch (_err) {}
  });

  ws.on("close", () => {
    if (currentRoom) {
      const p = currentRoom.players.get(myPlayerId);
      currentRoom.players.delete(myPlayerId);

      if (currentRoom.players.size === 0) {
        if (currentRoom.timerInterval) clearInterval(currentRoom.timerInterval);
        if (currentRoom.itemSpawnInterval) clearInterval(currentRoom.itemSpawnInterval);
        active3DRooms.delete(currentRoom.code);
        console.log(`[WS Server] Room ${currentRoom.code} deleted (empty).`);
      } else {
        broadcastToRoom(currentRoom, "player_left", {
          id: myPlayerId,
          name: p ? p.name : "Player",
          playersCount: currentRoom.players.size
        });

        if (currentRoom.hostId === myPlayerId) {
          const newHostKey = currentRoom.players.keys().next().value;
          if (newHostKey) {
            currentRoom.hostId = newHostKey;
            broadcastToRoom(currentRoom, "host_changed", { newHostId: newHostKey });
          }
        }
        check3DEndCondition(currentRoom);
      }
    }
  });
});

function start3DRound(room: Active3DRoom) {
  room.phase = "playing";
  room.timeLeft = 165; // 02:45

  // Assign roles (1 tagger, others runners)
  const pKeys = Array.from(room.players.keys());
  const taggerIdx = Math.floor(Math.random() * pKeys.length);

  pKeys.forEach((id, i) => {
    const p = room.players.get(id)!;
    p.role = i === taggerIdx ? "tagger" : "runner";
    p.frozen = false;
    p.isRescuing = false;
    p.hasShield = false;
    p.heldItem = "";
    const sp = SPAWN_3D_POSITIONS[i % SPAWN_3D_POSITIONS.length];
    p.x = sp.x;
    p.y = sp.y;
    p.z = sp.z;
  });

  // Spawn initial items
  room.items.clear();
  const types = ["speed", "shield", "heater", "banana", "vortex", "tackle"];
  for (let i = 0; i < 4; i++) {
    const id = `item_${++room.itemCounter}`;
    const t = types[Math.floor(Math.random() * types.length)];
    const x = Math.round((Math.random() * 40 - 20) * 10) / 10;
    const z = Math.round((Math.random() * 40 - 20) * 10) / 10;
    room.items.set(id, { id, type: t, x, y: 0.6, z });
  }

  const pList = Array.from(room.players.values()).map(p => ({
    id: p.id,
    name: p.name,
    role: p.role,
    x: p.x,
    y: p.y,
    z: p.z
  }));

  const itemsList = Array.from(room.items.values());

  broadcastToRoom(room, "round_started", {
    round: room.currentRound,
    maxRounds: room.rounds,
    timeLeft: room.timeLeft,
    players: pList,
    items: itemsList
  });

  if (room.timerInterval) clearInterval(room.timerInterval);
  room.timerInterval = setInterval(() => {
    if (room.phase !== "playing") return;
    room.timeLeft -= 1;
    if (room.timeLeft % 5 === 0 || room.timeLeft <= 10) {
      broadcastToRoom(room, "time_sync", { timeLeft: room.timeLeft });
    }
    if (room.timeLeft <= 0) {
      end3DRound(room, "RUNNERS", "Time Expired");
    }
  }, 1000);

  if (room.itemSpawnInterval) clearInterval(room.itemSpawnInterval);
  room.itemSpawnInterval = setInterval(() => {
    if (room.phase !== "playing" || room.items.size >= 6) return;
    const id = `item_${++room.itemCounter}`;
    const t = types[Math.floor(Math.random() * types.length)];
    const x = Math.round((Math.random() * 40 - 20) * 10) / 10;
    const z = Math.round((Math.random() * 40 - 20) * 10) / 10;
    room.items.set(id, { id, type: t, x, y: 0.6, z });
    broadcastToRoom(room, "item_spawned", { id, type: t, x, y: 0.6, z });
  }, 9000);
}

function check3DEndCondition(room: Active3DRoom) {
  if (room.phase !== "playing") return;
  let activeRunners = 0;
  room.players.forEach(p => {
    if (p.role === "runner" && !p.frozen) activeRunners++;
  });
  if (activeRunners === 0) {
    end3DRound(room, "TAGGERS", "All Runners Frozen");
  }
}

function end3DRound(room: Active3DRoom, winner: "TAGGERS" | "RUNNERS", reason: string) {
  if (room.phase === "ended") return;
  room.phase = "ended";
  if (room.timerInterval) clearInterval(room.timerInterval);
  if (room.itemSpawnInterval) clearInterval(room.itemSpawnInterval);

  if (winner === "TAGGERS") room.taggersScore++;
  else room.runnersScore++;

  let best: ActivePlayer | null = null;
  let maxPts = -1;
  room.players.forEach(p => {
    const pts = p.freezeCount * 2 + p.rescueCount * 2;
    if (pts > maxPts) { maxPts = pts; best = p; }
  });

  const isMatchOver = room.currentRound >= room.rounds;

  broadcastToRoom(room, "round_ended", {
    winner,
    reason,
    runnersScore: room.runnersScore,
    taggersScore: room.taggersScore,
    currentRound: room.currentRound,
    maxRounds: room.rounds,
    isMatchOver,
    mvp: best ? {
      id: (best as ActivePlayer).id,
      name: (best as ActivePlayer).name,
      freezeCount: (best as ActivePlayer).freezeCount,
      rescueCount: (best as ActivePlayer).rescueCount
    } : null
  });
}

// ── Start HTTP & WebSocket Server ───────────────────────────────────────────
async function start() {
  server.listen(PORT, "0.0.0.0", () => {
    console.log(`\n🎮 CPFreezeTag-3D Server listening on 0.0.0.0:${PORT}`);
    console.log(`   - Colyseus Room: "game_room"`);
    console.log(`   - WebSocket: ws://0.0.0.0:${PORT}/ws`);
    console.log(`   - REST API: http://0.0.0.0:${PORT}/api/rooms`);
    console.log(`   - Health: http://0.0.0.0:${PORT}/health`);
    console.log(`   - Static Client: ${clientBuildPath}`);
  });
}

start().catch((err) => {
  console.error("❌ Failed to start server:", err);
  process.exit(1);
});
