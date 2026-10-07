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
  hp: number;
  invincibleUntil: number;
  isReady: boolean;
  lastTackleTime?: number;
}

export interface Active3DRoom {
  code: string;
  name: string;
  hostId: string;
  maxPlayers: number;
  rounds: number;
  currentRound: number;
  map: string;
  isPrivate: boolean;
  phase: "lobby" | "playing" | "ended";
  timeLeft: number;
  runnersScore: number;
  taggersScore: number;
  players: Map<string, ActivePlayer>;
  items: Map<string, { id: string; type: string; x: number; y: number; z: number }>;
  timerInterval: NodeJS.Timeout | null;
  itemSpawnInterval: NodeJS.Timeout | null;
  itemCounter: number;
  kickedPlayerIds?: Set<string>;
}

const active3DRooms: Map<string, Active3DRoom> = new Map();
const MAX_TOTAL_ROOMS = 50; // Maximum concurrent rooms to prevent memory overflow
const ROOM_CREATE_COOLDOWN_MS = 3000; // 3 seconds cooldown per player

// Ghost Room & Dead Socket Sweeper
function cleanupGhostRooms() {
  for (const [code, r] of active3DRooms.entries()) {
    let deletedCount = 0;
    // Remove any player whose WebSocket is no longer OPEN
    for (const [pId, p] of r.players.entries()) {
      if (!p.ws || p.ws.readyState !== WebSocket.OPEN) {
        const leftName = p.name || "Player";
        r.players.delete(pId);
        deletedCount++;
        broadcastToRoom(r, "player_left", {
          id: pId,
          name: leftName,
          playersCount: r.players.size
        });
      }
    }
    // If room has 0 players, purge it immediately from RAM
    if (r.players.size === 0) {
      if (r.timerInterval) clearInterval(r.timerInterval);
      if (r.itemSpawnInterval) clearInterval(r.itemSpawnInterval);
      active3DRooms.delete(code);
      console.log(`[Cleaner] Ghost room ${code} purged (0 active players).`);
    } else {
      if (!r.players.has(r.hostId)) {
        const newHost = r.players.keys().next().value;
        if (newHost) {
          r.hostId = newHost;
          const hostPlayer = r.players.get(newHost);
          if (hostPlayer) hostPlayer.isReady = true;
          const pList: any[] = [];
          r.players.forEach((pl) => {
            pList.push({
              id: pl.id,
              name: pl.name,
              isHost: pl.id === r.hostId,
              isReady: pl.id === r.hostId ? true : Boolean(pl.isReady)
            });
          });
          broadcastToRoom(r, "host_changed", {
            newHostId: newHost,
            hostName: hostPlayer?.name || "Host",
            players: pList
          });
        }
      }
      if (deletedCount > 0) {
        check3DEndCondition(r);
      }
    }
  }
}
setInterval(cleanupGhostRooms, 1000);

// Public rooms API for Godot Lobby Browser (private rooms excluded)
app.get("/api/rooms", async (_req, res) => {
  cleanupGhostRooms();
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
    if (r.isPrivate) return; // Do not display private rooms in public list
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

// ── Application-Level Heartbeat & Idle Timeout (Detect Half-Open Connections) ──
// Checks every 10 seconds. Sockets are kept alive by:
// 1. Any client message (movement, action, chat)
// 2. Client keepalive ping: { action: "ping" }
// 3. Low-level WebSocket pong response
// If a client is completely silent for > 35 seconds, it is terminated as a dead socket.
const HEARTBEAT_CHECK_INTERVAL_MS = 10000;
const SOCKET_IDLE_TIMEOUT_MS = 35000;

const heartbeatInterval = setInterval(() => {
  const now = Date.now();
  wss.clients.forEach((client) => {
    const ws = client as WebSocket & { lastActiveTime?: number };
    const lastActive = ws.lastActiveTime ?? now;
    if (now - lastActive > SOCKET_IDLE_TIMEOUT_MS) {
      console.log(`[Heartbeat] Terminating dead/half-open socket (silent for ${((now - lastActive) / 1000).toFixed(1)}s).`);
      return ws.terminate();
    }
    try {
      ws.ping();
    } catch (_err) {
      ws.terminate();
    }
  });
}, HEARTBEAT_CHECK_INTERVAL_MS);

wss.on("close", () => {
  clearInterval(heartbeatInterval);
});

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
  const extWs = ws as WebSocket & { lastActiveTime?: number };
  extWs.lastActiveTime = Date.now();

  ws.on("pong", () => {
    extWs.lastActiveTime = Date.now();
  });

  let currentRoom: Active3DRoom | null = null;
  let myPlayerId = `p_${Math.random().toString(36).substring(2, 9)}`;
  let lastRoomCreateTime = 0;
  let lastJoinAttemptTime = 0;
  let failedJoinAttempts = 0;
  let lockoutUntil = 0;

  ws.on("message", (rawMsg: Buffer | string) => {
    extWs.lastActiveTime = Date.now();
    try {
      const msg = JSON.parse(rawMsg.toString());
      const action = msg.action || msg.type || "";

      switch (action) {
        // Set Player Name
        case "set_player_name": {
          const newName = String(msg.name || "Player").trim().slice(0, 16);
          if (currentRoom) {
            const p = currentRoom.players.get(myPlayerId);
            if (p) {
              p.name = newName;
              broadcastToRoom(currentRoom, "player_name_updated", {
                id: myPlayerId,
                name: newName
              });
            }
          }
          break;
        }

        // 1. Create Room (Host with Rate Limiting & Room Cap)
        case "create_room": {
          const now = Date.now();
          // Rate Limit Check 1: Cooldown (3 seconds)
          if (now - lastRoomCreateTime < ROOM_CREATE_COOLDOWN_MS) {
            sendTo(ws, "error", { message: "Please wait 3 seconds before creating another room." });
            return;
          }

          // Rate Limit Check 2: Already in a room
          if (currentRoom) {
            sendTo(ws, "error", { message: "You are already in an active room! Leave first." });
            return;
          }

          // Rate Limit Check 3: Server maximum concurrent rooms capacity
          if (active3DRooms.size >= MAX_TOTAL_ROOMS) {
            sendTo(ws, "error", { message: `Server room limit reached (max ${MAX_TOTAL_ROOMS} rooms). Please join an existing room.` });
            return;
          }

          lastRoomCreateTime = now;
          const code = generateCode();
          const rName = String(msg.roomName || `Room ${code}`);
          const pName = String(msg.playerName || "Host").slice(0, 16);
          const maxP = Math.max(4, Math.min(8, Number(msg.maxPlayers) || 8));
          const rounds = Math.max(1, Math.min(5, Number(msg.rounds) || 3));
          const map = String(msg.map || "CASTLE");
          const isPrivate = Boolean(msg.isPrivate);

          const newRoom: Active3DRoom = {
            code,
            name: rName,
            hostId: myPlayerId,
            maxPlayers: maxP,
            rounds,
            currentRound: 1,
            map,
            isPrivate,
            phase: "lobby",
            timeLeft: 165,
            runnersScore: 0,
            taggersScore: 0,
            players: new Map(),
            items: new Map(),
            timerInterval: null,
            itemSpawnInterval: null,
            itemCounter: 0,
            kickedPlayerIds: new Set<string>()
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
            rescueCount: 0,
            hp: 100,
            invincibleUntil: 0,
            isReady: true // Host is ready by default
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
            isPrivate,
            players: [{ id: p.id, name: p.name, isHost: true, isReady: true }]
          });
          console.log(`[WS Server] Room created: ${code} (${isPrivate ? "PRIVATE" : "PUBLIC"}) by ${pName}`);
          break;
        }

        // Get Public Rooms List (Excludes private rooms & purges ghost rooms)
        case "get_rooms": {
          cleanupGhostRooms();
          const list: Array<any> = [];
          active3DRooms.forEach((r) => {
            if (r.isPrivate) return; // Do not send private rooms to public browser
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

        // 2. Join Room by Code (with Anti-Brute Force Protection)
        case "join_room": {
          cleanupGhostRooms();
          const now = Date.now();
          if (now < lockoutUntil) {
            const waitSec = Math.ceil((lockoutUntil - now) / 1000);
            sendTo(ws, "error", { message: `Too many failed attempts. Please wait ${waitSec}s.` });
            return;
          }
          if (now - lastJoinAttemptTime < 600) {
            sendTo(ws, "error", { message: "Joining too fast. Please slow down." });
            return;
          }
          lastJoinAttemptTime = now;

          const code = String(msg.roomCode || "").toUpperCase().trim();
          const pName = String(msg.playerName || "Player").slice(0, 16);

          const room = active3DRooms.get(code);
          if (!room) {
            failedJoinAttempts++;
            if (failedJoinAttempts >= 5) {
              lockoutUntil = now + 5000; // 5-second lockout after 5 consecutive failures
              failedJoinAttempts = 0;
            }
            sendTo(ws, "error", { message: `Room not found: "${code}"` });
            return;
          }
          failedJoinAttempts = 0; // Reset on valid room code
          if (room.phase !== "lobby") {
            sendTo(ws, "error", { message: `Match already in progress for room "${code}"` });
            return;
          }
          if (room.kickedPlayerIds && room.kickedPlayerIds.has(myPlayerId)) {
            sendTo(ws, "error", { message: `You have been kicked from room "${code}" and cannot rejoin.` });
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
            rescueCount: 0,
            hp: 100,
            invincibleUntil: 0,
            isReady: false // Non-host joins as not ready
          };

          room.players.set(myPlayerId, newPlayer);
          currentRoom = room;

          const pList = Array.from(room.players.values()).map(pl => ({
            id: pl.id,
            name: pl.name,
            isHost: pl.id === room.hostId,
            isReady: pl.id === room.hostId ? true : Boolean(pl.isReady)
          }));

          sendTo(ws, "room_joined", {
            code: room.code,
            name: room.name,
            myId: myPlayerId,
            isHost: myPlayerId === room.hostId,
            maxPlayers: room.maxPlayers,
            rounds: room.rounds,
            map: room.map,
            isPrivate: room.isPrivate,
            players: pList
          });

          broadcastToRoom(room, "player_joined", {
            id: newPlayer.id,
            name: newPlayer.name,
            isHost: false,
            isReady: false,
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
          if (typeof msg.isPrivate === "boolean") currentRoom.isPrivate = msg.isPrivate;

          broadcastToRoom(currentRoom, "settings_updated", {
            maxPlayers: currentRoom.maxPlayers,
            rounds: currentRoom.rounds,
            map: currentRoom.map,
            isPrivate: currentRoom.isPrivate
          }, ws);
          break;
        }

        // Set Ready State (Non-Host)
        case "set_ready": {
          if (!currentRoom) return;
          const room = currentRoom;
          const p = room.players.get(myPlayerId);
          if (!p) return;
          p.isReady = Boolean(msg.isReady !== undefined ? msg.isReady : !p.isReady);

          const pList = Array.from(room.players.values()).map(pl => ({
            id: pl.id,
            name: pl.name,
            isHost: pl.id === room.hostId,
            isReady: pl.id === room.hostId ? true : Boolean(pl.isReady)
          }));

          broadcastToRoom(room, "player_ready_updated", {
            id: myPlayerId,
            isReady: p.isReady,
            players: pList
          });
          break;
        }

        // 4. Start Game (Host - Validates that all non-host players are READY)
        case "start_game": {
          if (!currentRoom) return;
          if (currentRoom.hostId !== myPlayerId) {
            console.warn(`[start_game] Rejected: player ${myPlayerId} is not host (${currentRoom.hostId})`);
            sendTo(ws, "error", { message: "Only the room host can start the game!" });
            return;
          }
          const room = currentRoom;
          const hostPlayer = room.players.get(room.hostId);
          if (hostPlayer) hostPlayer.isReady = true;

          // Check if all other players are ready!
          let unreadyCount = 0;
          room.players.forEach(p => {
            if (p.id !== room.hostId && !p.isReady) {
              unreadyCount++;
            }
          });

          if (unreadyCount > 0) {
            sendTo(ws, "error", { message: `Cannot start! Waiting for ${unreadyCount} player(s) to press READY.` });
            return;
          }

          start3DRound(room);
          break;
        }

        // Return to Lobby (Host)
        case "return_to_lobby": {
          if (!currentRoom || currentRoom.hostId !== myPlayerId) return;
          const room = currentRoom;
          room.phase = "lobby";
          if (room.timerInterval) clearInterval(room.timerInterval);
          if (room.itemSpawnInterval) clearInterval(room.itemSpawnInterval);
          room.items.clear();
          room.currentRound = 1;
          room.runnersScore = 0;
          room.taggersScore = 0;

          room.players.forEach(p => {
            p.frozen = false;
            p.isRescuing = false;
            p.hasShield = false;
            p.heldItem = "";
            p.freezeCount = 0;
            p.rescueCount = 0;
            p.hp = 100;
            p.invincibleUntil = 0;
            p.isReady = (p.id === room.hostId); // Host is ready, non-hosts must ready up again
          });

          const pList = Array.from(room.players.values()).map(pl => ({
            id: pl.id,
            name: pl.name,
            isHost: pl.id === room.hostId,
            isReady: pl.id === room.hostId ? true : Boolean(pl.isReady)
          }));

          broadcastToRoom(room, "returned_to_lobby", {
            code: room.code,
            name: room.name,
            hostId: room.hostId,
            maxPlayers: room.maxPlayers,
            rounds: room.rounds,
            map: room.map,
            isPrivate: room.isPrivate,
            players: pList
          });
          break;
        }

        // Kick Player (Host only)
        case "kick_player": {
          if (!currentRoom) return;
          const room = currentRoom;
          if (room.hostId !== myPlayerId) {
            sendTo(ws, "error", { message: "Only the room host can kick players." });
            return;
          }
          const targetId = String(msg.targetId || "");
          if (!targetId || targetId === myPlayerId) {
            sendTo(ws, "error", { message: "Cannot kick yourself or invalid target." });
            return;
          }
          const targetPlayer = room.players.get(targetId);
          if (!targetPlayer) {
            sendTo(ws, "error", { message: "Player not found in this room." });
            return;
          }

          if (!room.kickedPlayerIds) {
            room.kickedPlayerIds = new Set<string>();
          }
          room.kickedPlayerIds.add(targetId);
          room.players.delete(targetId);

          // Notify the kicked player directly
          if (targetPlayer.ws && targetPlayer.ws.readyState === WebSocket.OPEN) {
            sendTo(targetPlayer.ws, "kicked_from_room", {
              reason: "You were kicked by the room host."
            });
          }

          // Broadcast updated player list to remaining players in room
          const pList = Array.from(room.players.values()).map(pl => ({
            id: pl.id,
            name: pl.name,
            isHost: pl.id === room.hostId,
            isReady: pl.id === room.hostId ? true : Boolean(pl.isReady)
          }));

          broadcastToRoom(room, "player_left", {
            id: targetId,
            name: targetPlayer.name,
            reason: "kicked",
            playersCount: room.players.size,
            players: pList
          });

          if (room.phase === "playing") {
            check3DEndCondition(room);
          }

          console.log(`[WS Server] Player "${targetPlayer.name}" (${targetId}) was kicked from room ${room.code} by host ${myPlayerId}`);
          break;
        }

        // Leave Room explicitly
        case "leave_room": {
          if (currentRoom) {
            const roomToLeave = currentRoom;
            const p = roomToLeave.players.get(myPlayerId);
            roomToLeave.players.delete(myPlayerId);

            if (roomToLeave.players.size === 0) {
              if (roomToLeave.timerInterval) clearInterval(roomToLeave.timerInterval);
              if (roomToLeave.itemSpawnInterval) clearInterval(roomToLeave.itemSpawnInterval);
              active3DRooms.delete(roomToLeave.code);
              console.log(`[WS Server] Room ${roomToLeave.code} deleted by leave_room.`);
            } else {
              if (roomToLeave.hostId === myPlayerId) {
                const newHostKey = roomToLeave.players.keys().next().value;
                if (newHostKey) {
                  roomToLeave.hostId = newHostKey;
                  const newHost = roomToLeave.players.get(newHostKey);
                  if (newHost) newHost.isReady = true;
                  const pList: any[] = [];
                  roomToLeave.players.forEach((pl) => {
                    pList.push({
                      id: pl.id,
                      name: pl.name,
                      isHost: pl.id === roomToLeave.hostId,
                      isReady: pl.id === roomToLeave.hostId ? true : Boolean(pl.isReady)
                    });
                  });
                  broadcastToRoom(roomToLeave, "host_changed", {
                    newHostId: newHostKey,
                    hostName: newHost?.name || "Host",
                    players: pList
                  });
                }
              }
              broadcastToRoom(roomToLeave, "player_left", {
                id: myPlayerId,
                name: p ? p.name : "Player",
                playersCount: roomToLeave.players.size
              });
              check3DEndCondition(roomToLeave);
            }
            currentRoom = null;
            sendTo(ws, "left_room", {});
            cleanupGhostRooms();
          }
          break;
        }

        // 5. 3D Movement (with coordinate & NaN/Infinity sanity check)
        case "move": {
          if (!currentRoom || currentRoom.phase !== "playing") return;
          const p = currentRoom.players.get(myPlayerId);
          if (!p || p.frozen) return;

          const rawX = Number(msg.x);
          const rawY = Number(msg.y);
          const rawZ = Number(msg.z);

          // Discard NaN, Infinity, or out-of-bounds coordinates (-40m to +40m)
          if (!Number.isFinite(rawX) || !Number.isFinite(rawY) || !Number.isFinite(rawZ)) return;
          if (Math.abs(rawX) > 40 || Math.abs(rawZ) > 40 || rawY < -10 || rawY > 30) return;

          p.x = rawX;
          p.y = rawY;
          p.z = rawZ;
          if (typeof msg.rotY === "number" && Number.isFinite(msg.rotY)) p.rotY = msg.rotY;

          broadcastToRoom(currentRoom, "player_moved", {
            id: myPlayerId,
            x: p.x,
            y: p.y,
            z: p.z,
            rotY: p.rotY
          }, ws);
          break;
        }

        // 6. Tag Player (with Distance & Immunity verification)
        case "tag_player": {
          if (!currentRoom || currentRoom.phase !== "playing") return;
          const tagger = currentRoom.players.get(myPlayerId);
          const victim = currentRoom.players.get(String(msg.victimId));
          if (!tagger || !victim || tagger.role !== "tagger" || victim.role !== "runner" || victim.frozen) return;

          // Anti-Cheat: Validate Euclidean distance between Tagger and Victim
          const dist = Math.hypot(tagger.x - victim.x, tagger.z - victim.z);
          const MAX_TAG_DIST = 4.5; // Max reach (1.5m collision radius + latency/speed buffer)
          if (dist > MAX_TAG_DIST) {
            console.warn(`[AntiCheat] Blocked distant tag attempt by ${tagger.name} on ${victim.name} (${dist.toFixed(2)}m)`);
            return;
          }

          // Runner is immune from Dash Tackle!
          if (victim.invincibleUntil && victim.invincibleUntil > Date.now()) {
            return;
          }

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

        // 7. Rescue Player (with Distance verification)
        case "rescue_player": {
          if (!currentRoom || currentRoom.phase !== "playing") return;
          const rescuer = currentRoom.players.get(myPlayerId);
          const victim = currentRoom.players.get(String(msg.victimId));
          if (!rescuer || !victim || rescuer.role !== "runner" || rescuer.frozen || !victim.frozen) return;

          // Anti-Cheat: Validate Euclidean distance
          const dist = Math.hypot(rescuer.x - victim.x, rescuer.z - victim.z);
          const MAX_RESCUE_DIST = 4.5;
          if (dist > MAX_RESCUE_DIST) {
            console.warn(`[AntiCheat] Blocked distant rescue attempt by ${rescuer.name} on ${victim.name} (${dist.toFixed(2)}m)`);
            return;
          }

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
            const rotY = p.rotY || 0;
            const bx = Math.round((p.x + Math.sin(rotY) * 1.8) * 100) / 100;
            const bz = Math.round((p.z + Math.cos(rotY) * 1.8) * 100) / 100;
            broadcastToRoom(currentRoom, "banana_placed", {
              x: bx,
              y: 0.05,
              z: bz,
              placerId: p.id
            });
          } else if (itemType === "vortex") {
            // Teleport user to random location on map
            p.x = Math.round((Math.random() * 40 - 20) * 10) / 10;
            p.z = Math.round((Math.random() * 40 - 20) * 10) / 10;
            broadcastToRoom(currentRoom, "player_moved", { id: p.id, x: p.x, y: p.y, z: p.z, rotY: p.rotY });
            broadcastToRoom(currentRoom, "chat_message", { msg: `🌀 ${p.name} teleported across the arena!` });
          } else if (itemType === "tackle") {
            p.invincibleUntil = Date.now() + 3000; // 1s dash + 2s immunity
            broadcastToRoom(currentRoom, "chat_message", { msg: `💥 ${p.name} activated Dash Tackle! (Immunity active)` });
          } else if (itemType === "heater") {
            if (p.frozen) {
              p.frozen = false;
              broadcastToRoom(currentRoom, "player_unfrozen", { playerId: p.id });
            }
          }
          break;
        }

        // 11. Tackle Player (Runner dashes into Tagger with Cooldown & Distance verification)
        case "tackle_player": {
          if (!currentRoom || currentRoom.phase !== "playing") return;
          const runner = currentRoom.players.get(myPlayerId);
          const tagger = currentRoom.players.get(String(msg.targetId));
          if (!runner || !tagger || runner.role !== "runner" || tagger.role !== "tagger") return;

          const now = Date.now();
          // Anti-Spam: Enforce 2.0s cooldown per runner on server
          if (runner.lastTackleTime && now - runner.lastTackleTime < 2000) {
            return;
          }

          // Anti-Cheat: Validate Euclidean distance between Runner and Tagger
          const dist = Math.hypot(runner.x - tagger.x, runner.z - tagger.z);
          const MAX_TACKLE_DIST = 5.0; // Dash tackle reach
          if (dist > MAX_TACKLE_DIST) {
            console.warn(`[AntiCheat] Blocked distant tackle attempt by ${runner.name} on ${tagger.name} (${dist.toFixed(2)}m)`);
            return;
          }

          runner.lastTackleTime = now;
          tagger.hp = Math.max(0, (tagger.hp !== undefined ? tagger.hp : 100) - 20);
          runner.invincibleUntil = now + 2000; // 2 seconds invulnerability upon hit

          broadcastToRoom(currentRoom, "player_damaged", {
            targetId: tagger.id,
            targetName: tagger.name,
            attackerId: runner.id,
            attackerName: runner.name,
            amount: 20,
            currentHp: tagger.hp
          });
          broadcastToRoom(currentRoom, "chat_message", {
            msg: `💥 ${runner.name} tackled ${tagger.name}! (-20 HP, 2s Immunity)`
          });

          if (tagger.hp <= 0) {
            broadcastToRoom(currentRoom, "chat_message", {
              msg: `👑 Tagger ${tagger.name} ran out of HP! RUNNERS WIN!`
            });
            end3DRound(currentRoom, "RUNNERS", "Taggers Defeated");
          }
          break;
        }

        // 12. Place Banana Trap
        case "place_banana": {
          if (!currentRoom || currentRoom.phase !== "playing") return;
          const p = currentRoom.players.get(myPlayerId);
          if (!p) return;
          const bx = Number(msg.x) || p.x;
          const by = Number(msg.y) || 0.05;
          const bz = Number(msg.z) || p.z;
          broadcastToRoom(currentRoom, "banana_placed", {
            x: bx,
            y: by,
            z: bz,
            placerId: p.id
          });
          break;
        }

        // 13. Application-layer Ping / Pong for RTT latency checks & keep-alive
        case "ping": {
          extWs.lastActiveTime = Date.now();
          sendTo(ws, "pong", {
            clientTime: msg.time ?? msg.timestamp ?? 0,
            serverTime: Date.now()
          });
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
        const room = currentRoom;
        if (room.hostId === myPlayerId) {
          const newHostKey = room.players.keys().next().value;
          if (newHostKey) {
            room.hostId = newHostKey;
            const newHost = room.players.get(newHostKey);
            if (newHost) newHost.isReady = true;
            const pList: any[] = [];
            room.players.forEach((pl) => {
              pList.push({
                id: pl.id,
                name: pl.name,
                isHost: pl.id === room.hostId,
                isReady: pl.id === room.hostId ? true : Boolean(pl.isReady)
              });
            });
            broadcastToRoom(room, "host_changed", {
              newHostId: newHostKey,
              hostName: newHost?.name || "Host",
              players: pList
            });
          }
        }
        broadcastToRoom(room, "player_left", {
          id: myPlayerId,
          name: p ? p.name : "Player",
          playersCount: room.players.size
        });
        check3DEndCondition(room);
      }
    }
    cleanupGhostRooms();
  });
});

function start3DRound(room: Active3DRoom) {
  if (room.phase === "ended") {
    if (room.currentRound >= room.rounds) {
      room.currentRound = 1;
      room.runnersScore = 0;
      room.taggersScore = 0;
      room.players.forEach(p => { p.freezeCount = 0; p.rescueCount = 0; });
    } else {
      room.currentRound++;
    }
  }

  room.phase = "playing";
  room.timeLeft = 165; // 02:45

  // Assign roles (1 tagger, others runners)
  const pKeys = Array.from(room.players.keys());
  const taggerIdx = Math.floor(Math.random() * pKeys.length);

  const mapUpper = (room.map || "").toUpperCase();
  const isSpaceStation = mapUpper.includes("SPACE");
  const isSnowTown = mapUpper.includes("SNOW") || mapUpper.includes("TOWN") || mapUpper.includes("หิมะ");
  const isLabyrinth = mapUpper.includes("LABYRINTH") || mapUpper.includes("MAZE") || mapUpper.includes("เขาวงกต");

  const spaceStationRunnerSpawns = [
    { x: 0, y: 0.5, z: 22 },
    { x: -22, y: 0.5, z: 0 },
    { x: -20, y: 0.5, z: -20 },
    { x: 20, y: 0.5, z: 20 },
    { x: -20, y: 0.5, z: 20 },
    { x: 20, y: 0.5, z: -20 }
  ];
  const snowTownRunnerSpawns = [
    { x: 14.0, y: 0.5, z: -8.0 },
    { x: -18.0, y: 0.6, z: 10.0 },
    { x: 18.0, y: 0.6, z: 14.0 },
    { x: 0.0, y: 0.8, z: -2.0 },
    { x: -16.0, y: 0.6, z: 0.0 },
    { x: 4.0, y: 0.6, z: 0.0 }
  ];
  const labyrinthRunnerSpawns = [
    { x: -15.0, y: 6.0, z: 12.0 },
    { x: 16.0, y: 5.3, z: 14.0 },
    { x: 7.0, y: 5.1, z: 3.0 },
    { x: 16.0, y: 5.4, z: -2.0 },
    { x: -16.0, y: 5.2, z: 6.0 },
    { x: -5.0, y: 5.0, z: -2.0 }
  ];
  let runnerSpawnIdx = 0;

  pKeys.forEach((id, i) => {
    const p = room.players.get(id)!;
    p.role = i === taggerIdx ? "tagger" : "runner";
    p.frozen = false;
    p.isRescuing = false;
    p.hasShield = false;
    p.heldItem = "";
    p.hp = 100;
    p.invincibleUntil = 0;

    if (isSpaceStation) {
      if (p.role === "tagger") {
        p.x = 0; p.y = 0.5; p.z = -22;
      } else {
        const sp = spaceStationRunnerSpawns[runnerSpawnIdx % spaceStationRunnerSpawns.length];
        p.x = sp.x; p.y = sp.y; p.z = sp.z;
        runnerSpawnIdx++;
      }
    } else if (isSnowTown) {
      if (p.role === "tagger") {
        p.x = -14.0; p.y = 0.6; p.z = -14.0;
      } else {
        const sp = snowTownRunnerSpawns[runnerSpawnIdx % snowTownRunnerSpawns.length];
        p.x = sp.x; p.y = sp.y; p.z = sp.z;
        runnerSpawnIdx++;
      }
    } else if (isLabyrinth) {
      if (p.role === "tagger") {
        p.x = -15.0; p.y = 5.6; p.z = -16.0;
      } else {
        const sp = labyrinthRunnerSpawns[runnerSpawnIdx % labyrinthRunnerSpawns.length];
        p.x = sp.x; p.y = sp.y; p.z = sp.z;
        runnerSpawnIdx++;
      }
    } else {
      const sp = SPAWN_3D_POSITIONS[i % SPAWN_3D_POSITIONS.length];
      p.x = sp.x;
      p.y = sp.y;
      p.z = sp.z;
    }
  });

  // Spawn initial items
  room.items.clear();
  const types = ["speed", "shield", "heater", "banana", "vortex", "tackle"];
  const itemSpots = [
    { x: 0, y: 0.6, z: 0 },
    { x: -16, y: 0.6, z: -15 },
    { x: -16, y: 0.6, z: 15 },
    { x: 16, y: 0.6, z: 15 },
    { x: 22, y: 0.6, z: 0 },
    { x: -22, y: 0.6, z: 0 }
  ];
  for (let i = 0; i < 4; i++) {
    const id = `item_${++room.itemCounter}`;
    const t = types[Math.floor(Math.random() * types.length)];
    let x: number, y: number = 0.6, z: number;
    if (isSpaceStation) {
      const spot = itemSpots[i % itemSpots.length];
      x = spot.x + Math.round((Math.random() * 2 - 1) * 10) / 10;
      y = spot.y;
      z = spot.z + Math.round((Math.random() * 2 - 1) * 10) / 10;
    } else if (isSnowTown) {
      const spots = [
        { x: 0.0, y: 0.8, z: -2.0 },
        { x: 4.0, y: 0.6, z: 0.0 },
        { x: -12.0, y: 0.6, z: 18.0 },
        { x: 6.0, y: 0.5, z: -12.0 },
        { x: 10.0, y: 0.6, z: -2.0 },
        { x: -20.0, y: 0.6, z: 10.0 },
        { x: 18.0, y: 0.5, z: -6.0 }
      ];
      const spot = spots[i % spots.length];
      x = spot.x;
      y = spot.y;
      z = spot.z;
    } else if (isLabyrinth) {
      const spots = [
        { x: -4.0, y: 5.1, z: -2.0 },
        { x: -14.0, y: 5.4, z: 15.0 },
        { x: 8.0, y: 5.2, z: -6.0 },
        { x: 12.0, y: 5.4, z: 10.0 },
        { x: -10.0, y: 5.2, z: 5.0 },
        { x: 5.0, y: 5.0, z: -12.0 }
      ];
      const spot = spots[i % spots.length];
      x = spot.x;
      y = spot.y;
      z = spot.z;
    } else {
      x = Math.round((Math.random() * 40 - 20) * 10) / 10;
      z = Math.round((Math.random() * 40 - 20) * 10) / 10;
    }
    room.items.set(id, { id, type: t, x, y, z });
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
    items: itemsList,
    map: room.map
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
    let x: number, y: number = 0.6, z: number;
    if (isSpaceStation) {
      const spot = itemSpots[Math.floor(Math.random() * itemSpots.length)];
      x = spot.x; y = spot.y; z = spot.z;
    } else if (isSnowTown) {
      const spots = [
        { x: 0.0, y: 0.8, z: -2.0 },
        { x: 4.0, y: 0.6, z: 0.0 },
        { x: -12.0, y: 0.6, z: 18.0 },
        { x: 6.0, y: 0.5, z: -12.0 },
        { x: 10.0, y: 0.6, z: -2.0 },
        { x: -20.0, y: 0.6, z: 10.0 },
        { x: 18.0, y: 0.5, z: -6.0 }
      ];
      const spot = spots[Math.floor(Math.random() * spots.length)];
      x = spot.x; y = spot.y; z = spot.z;
    } else if (isLabyrinth) {
      const spots = [
        { x: -4.0, y: 5.1, z: -2.0 },
        { x: -14.0, y: 5.4, z: 15.0 },
        { x: 8.0, y: 5.2, z: -6.0 },
        { x: 12.0, y: 5.4, z: 10.0 },
        { x: -10.0, y: 5.2, z: 5.0 },
        { x: 5.0, y: 5.0, z: -12.0 }
      ];
      const spot = spots[Math.floor(Math.random() * spots.length)];
      x = spot.x; y = spot.y; z = spot.z;
    } else {
      x = Math.round((Math.random() * 40 - 20) * 10) / 10;
      z = Math.round((Math.random() * 40 - 20) * 10) / 10;
    }
    room.items.set(id, { id, type: t, x, y, z });
    broadcastToRoom(room, "item_spawned", { id, type: t, x, y, z });
  }, 9000);
}

function check3DEndCondition(room: Active3DRoom) {
  if (room.phase !== "playing") return;

  let taggersCount = 0;
  let activeRunners = 0;
  let totalRunners = 0;

  room.players.forEach(p => {
    if (p.role === "tagger") {
      taggersCount++;
    } else if (p.role === "runner") {
      totalRunners++;
      if (!p.frozen) activeRunners++;
    }
  });

  // 1. If all taggers left / disconnected, runners win immediately!
  if (taggersCount === 0) {
    broadcastToRoom(room, "chat_message", { msg: "👑 All Taggers left the match! RUNNERS WIN!" });
    end3DRound(room, "RUNNERS", "All Taggers Disconnected");
    return;
  }

  // 2. If no runners remain in the room, taggers win
  if (totalRunners === 0) {
    end3DRound(room, "TAGGERS", "All Runners Left");
    return;
  }

  // 3. If all remaining runners are frozen, taggers win
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
