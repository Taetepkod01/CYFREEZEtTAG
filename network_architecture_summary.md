# ❄️ CPFreezeTag-3D: Network Architecture & Technical Specification
> **เอกสารสรุปสถาปัตยกรรมระบบเครือข่าย (Network Architecture) สำหรับเตรียมสอบ / ถาม-ตอบ (Q&A)**
> รวบรวมข้อมูลจากการตรวจสอบซอร์สโค้ดจริง (Code-Inspected) พร้อมระบุไฟล์และเลขบรรทัดอย่างละเอียด

---

## 📌 บทนำสำหรับนำไปให้ Claude หรือกรรมการสอบถามต่อ
> *(สามารถ Copy ข้อความบล็อกนี้พร้อมเนื้อหาด้านล่างไปใส่ใน Claude เพื่อให้จำลองบทบาทเป็นกรรมการสอบได้ทันที)*
> 
> *"คุณคืออาจารย์ผู้ทรงคุณวุฒิด้าน Computer Networks และ Game Engine Architecture จงใช้ข้อมูลเชิงลึกของโปรเจกต์เกม FreezeTag 3D ด้านล่างนี้เพื่อตั้งคำถามเจาะลึก ตรวจสอบจุดแข็ง-จุดอ่อน สุ่มถามข้อจำกัด (Edge Cases) และให้คำแนะนำในการอัปเกรดระบบเพื่อใช้ในการสอบประเมินโปรเจกต์"*

---

## 1. Protocol & Communication Stack

| หัวข้อ | รายละเอียดทางเทคนิค | อ้างอิงโค้ดจริง |
| :--- | :--- | :--- |
| **Transport Protocol** | **TCP** (ผ่าน WebSocket / WSS) | `server/src/index.ts`: L6, L201 |
| **Server Library** | **`ws`** (v8.22.0) บน Node.js / Express 5 | `server/package.json`: L22 |
| **Client Library** | **`WebSocketPeer`** (Godot 4 Built-in WebAssembly) | `scripts/network.gd`: L46, L102 |
| **Data Format** | **JSON UTF-8 Text** (ไม่มีการใช้ Binary Buffer) | `network.gd`: L161, `index.ts`: L241 |
| **Connection Security** | **`wss://` (TLS 1.3 / HTTPS port 443)** บน Render Cloud<br>Fallback เป็น `ws://` เมื่อรันบน Local | `scripts/network.gd`: L77-89 |
| **Dynamic Host Detection** | Client ดึง `window.location.host` และ `protocol` อัตโนมัติ | `scripts/network.gd`: L80-88 |

---

## 2. Message Types & Payload Schemas

### รูปแบบ Message มาตรฐาน
* **Client $\rightarrow$ Server:** `{ "action": string, ...data }`
* **Server $\rightarrow$ Client:** `{ "event": string, "data": { ... } }`

### รายการคำสั่งสำคัญ (Client $\rightarrow$ Server)
1. **`create_room`** (`index.ts: L283`): `{ roomName, playerName, maxPlayers, rounds, map, isPrivate }`
2. **`join_room`** (`index.ts: L393`): `{ roomCode, playerName }`
3. **`set_ready`** (`index.ts: L487`): `{ isReady: boolean }`
4. **`start_game`** (`index.ts: L510`): บังคับว่าผู้เล่นที่ไม่ใช่ Host ทุกคนต้องพร้อมก่อน
5. **`move`** (`index.ts: L610`): `{ x, y, z, rotY }`
6. **`tag_player`** (`index.ts: L631`): `{ victimId }`
7. **`rescue_player`** (`index.ts: L662`): `{ victimId }`
8. **`tackle_player`** (`index.ts: L758`): `{ targetId }` (Runner ชน Tagger ลด 20 HP)
9. **`place_banana`** (`index.ts: L789`): `{ x, y, z }`
10. **`leave_room`** (`index.ts: L576`): ผู้เล่นแจ้งออกจากห้องก่อนปิดหน้าต่าง

### รายการอีเวนต์สำคัญ (Server $\rightarrow$ Client)
* `room_created`, `room_joined`, `player_joined`, `player_left`, `player_ready_updated`
* `round_started`, `time_sync`, `player_moved`, `player_tagged`, `player_rescued`
* `item_spawned`, `item_picked`, `item_used`, `banana_placed`, `player_damaged`
* `round_ended`, `returned_to_lobby`, `host_changed`, `error`

---

## 3. Architecture & Authority Division

* **Server-Authoritative (ควบคุมกฎและ State รวม):**
  * ดูแล Match Lifecycle: `lobby` $\rightarrow$ `playing` $\rightarrow$ `ended`
  * สุ่มบทบาท: 1 Tagger (Snowman) และ N Runners (Penguins) เมื่อเริ่มรอบ (`index.ts: L856-858`)
  * ตรวจสอบสิทธิ์การ Tag/Rescue: Tagger ต้องไม่ติดอมตะ, Runner มีโล่หรือไม่ (`index.ts: L631-657`)
  * จับเวลานับถอยหลัง (165 วินาที) และเสกไอเทมสุ่มทุก 9 วินาที (`index.ts: L1008-1058`)
  * คำนวณผู้ชนะและสถิติ MVP ประจำรอบ
* **Client-Authoritative (ควบคุมฟิสิกส์และการขยับ):**
  * Client ประมวลผล Physics การเดิน การกระโดด แรงโน้มถ่วง และการชนสิ่งกีดขวางในเครื่อง (`player_3d.gd: L186-256`)
  * Client ตรวจจับ Overlap ของตัวละคร (`Area3D`) แล้วยิง Trigger ไปขออนุมัติจาก Server (`player_3d.gd: L551-557`)
  * Server ทำหน้าที่เป็น Relay กระจายพิกัดโดย **ไม่มี Server-side Physics Simulation**

---

## 4. Real-time, Latency & Optimization

| ฟีเจอร์ | สถานะในโค้ด | รายละเอียดและการทำงาน |
| :--- | :---: | :--- |
| **Client Send Rate** | **20 Hz** | จำกัดเวลาส่งข้อมูลพิกัดทุกๆ 50ms (`network.gd: L68 MOVE_SEND_RATE = 0.05`) |
| **Delta Stationary Check** | **มี** | ถ้าผู้เล่นยืนนิ่ง ขยับไม่เกิน 0.04m และหันไม่เกิน 0.05 rad จะ **ไม่ส่งแพ็กเก็ต** (`player_3d.gd: L312-317`) |
| **Server Tick Rate** | **Event-Driven** | เซิร์ฟเวอร์กระจายแพ็กเก็ตแบบทันที (0ms delay) โดยไม่มี Fixed Loop ชะลอ |
| **Interpolation** | **มี** | ฝั่ง Client ใช้ `lerp(16.0 * delta)` และ `lerp_angle` เกลี่ยตำแหน่งผู้เล่นอื่นให้สมูท 60+ FPS (`player_3d.gd: L168-172`) |
| **Client Prediction** | **ไม่มี** | ตัวผู้เล่น Local ขยับทันทีโดยไม่ต้องรอ ACK จาก Server |
| **Lag Compensation** | **ไม่มี** | ไม่มีระบบย้อนเวลา Hitbox ตามปิง |

---

## 5. Connection Lifecycle & Disconnect Handling

* **Ghost Room & Dead Socket Sweeper:**
  * ฟังก์ชัน `cleanupGhostRooms()` ทำงานทุก 4 วินาที และทำงานซ้ำทุกครั้งที่มีการดึงรายชื่อห้อง (`index.ts: L80-105`)
  * ตรวจสอบถ้า Socket ใด `readyState !== WebSocket.OPEN` จะถูกคัดออกจากห้องทันที
  * หากห้องเหลือ 0 คน จะสั่งล้าง Interval Timer ทั้งหมด และลบห้องออกจาก RAM ทันที ป้องกัน Memory Leak
* **Host Migration:**
  * หาก Host หลุด ระบบจะส่งต่อตำแหน่ง Host ให้ผู้เล่นคนถัดไปทันที พร้อมส่งอีเวนต์ `host_changed` (`index.ts: L825-833`)
* **Chaser / Tagger Disconnect Rule (อัปเดตล่าสุด):**
  * ถ้า Tagger หลุดหรือออกจากห้องจนหมด (`taggersCount === 0`) ระหว่างแข่ง $\rightarrow$ **ฝ่าย Runners จะชนะทันที** โดยระบบจะ Broadcast แจ้งเตือนและจบเกมด้วยเหตุผล `"All Taggers Disconnected"` (`index.ts: L1069-1090`)
* **Runner Disconnect Rule:**
  * ถ้า Runner คนที่ถูกแช่แข็งหลุดไป แล้วทำให้ในห้องไม่เหลือ Runner ที่รอดชีวิตอยู่เลย (`activeRunners === 0`) $\rightarrow$ **ฝ่าย Taggers จะชนะทันที** ("All Runners Frozen")
* **Reconnection & Grace Period:**
  * **ไม่มี** การ Reconnect ด้วย Session Token (หากหลุดแล้วต่อใหม่จะได้ Player ID สุ่มใหม่เสมอ)

---

## 6. Capacity, Scalability & Bandwidth Estimation

* **ขีดจำกัดห้อง (Room Cap):** จำกัดสูงสุด 50 ห้องพร้อมกัน (`MAX_TOTAL_ROOMS = 50` ใน `index.ts: L76`)
* **Rate Limiting:**
  * จำกัดการสร้างห้อง: คูลดาวน์ 3 วินาทีต่อคน (`ROOM_CREATE_COOLDOWN_MS = 3000` ใน `index.ts: L77`)
  * การส่งคำสั่งการเล่นอื่นๆ: ใช้ Client-side Throttling (20 Hz)
* **การประเมิน Bandwidth:**
  * ขนาดแพ็กเก็ตพิกัด: ขาไป ~70 Bytes, ขากลับ ~100 Bytes (รวม TCP/WS Frame Header $\approx 150 \text{ Bytes}$)
  * ต่อผู้เล่น 1 คน (ห้อง 8 คน มีคนอื่นวิ่ง 7 คน):
    * อัปโหลด: $150 \text{ B} \times 20 \text{ Hz} \approx 3 \text{ KB/s}$ (~**24 Kbps**)
    * ดาวน์โหลด: $150 \text{ B} \times 20 \text{ Hz} \times 7 \approx 21 \text{ KB/s}$ (~**168 Kbps**)
  * สำหรับ 30 ห้องพร้อมกัน (240 ผู้เล่น Active พร้อมกัน):
    * Server Inbound: ~**5.76 Mbps**
    * Server Outbound: ~**40.3 Mbps** (~5 MB/s)

---

## 7. Security & Input Validation Analysis

* **ส่วนที่มีการ Validate ป้องกันไว้:**
  * **ชื่อผู้เล่น (Player Name):** แปลงเป็น String, ตัดช่องว่าง และจำกัดความยาวไม่เกิน 16 ตัวอักษร (`index.ts: L268`)
  * **จำนวนผู้เล่นและรอบการแข่ง:** Clamp ตัวเลขให้อยู่ในช่วง 4–8 คน และ 1–5 รอบ (`index.ts: L307-308`)
  * **รหัสห้อง (Room Code):** แปลงเป็นตัวพิมพ์ใหญ่ และจำกัดเฉพาะอักษรไร้ความกำกวม 32 ตัว (`CHARS`)
  * **การเริ่มเกม:** บังคับตรวจสอบสถานะ Ready ของผู้เล่นทุกคนก่อนเริ่ม (`index.ts: L513-524`)
* **จุดอ่อนที่ไม่มีในโค้ด (Known Limitations / จุดที่ควรทราบ):**
  1. **ไม่มี Server-side Speed Check:** ไม่ได้คำนวณระยะทางเทียบกับเวลาเพื่อตรวจ Speed Hack
  2. **ไม่มี Map Boundary Check:** Server ไม่ได้ตรวจสอบว่าค่าพิกัด $x, z$ หลุดออกนอกขอบเขตกำแพงหรือไม่
  3. **ไม่มี Payload Size Limiter ในระดับ Application:** พึ่งพาเพียง Buffer Limit พื้นฐานของไลบรารี `ws`
  4. **State หายเมื่อ Server Restart:** เก็บข้อมูลใน In-Memory RAM (`active3DRooms`) ไม่ได้เชื่อมต่อ Redis หรือ Database ภายนอก

---

## 8. Deployment Configuration
* **Service Provider:** Render.com
* **Configuration File:** `render.yaml` อยู่ที่ Root Directory
* **Build Command:** `npm install && npm run build`
* **Start Command:** `npm run start`
* **Static Client Serving:** ให้ Express โฮสต์ไฟล์ Web Build ของ Godot (`index.html`, `index.pck`, `index.wasm`) จากโฟลเดอร์ `server/public` พร้อมตั้งค่า Header `Cross-Origin-Opener-Policy: same-origin` และ `Cross-Origin-Embedder-Policy: require-corp` สำหรับ WebAssembly SharedArrayBuffer
