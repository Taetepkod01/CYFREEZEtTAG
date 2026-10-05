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

## 4. Real-time Synchronization via WebSocket (สถาปัตยกรรมการซิงค์แบบ Real-time)

| ฟีเจอร์ | สถานะในโค้ด | รายละเอียดและการทำงาน |
| :--- | :---: | :--- |
| **Transport Architecture** | **Full-Duplex Persistent Stream** | ใช้ท่อ WebSocket (TCP) ผ่านพอร์ต 443 (`wss://`) เชื่อมต่อค้างไว้ตลอดทั้งเกม ไม่ต้องทำ Handshake ซ้ำซ้อน |
| **Client Send Rate** | **20 Hz (ทุก 50ms)** | จำกัดเวลาส่งข้อมูลพิกัดการเคลื่อนที่ทุกๆ 50ms (`network.gd: L68 MOVE_SEND_RATE = 0.05`) ป้องกันการ Flooding ท่อเน็ต |
| **Stationary Threshold Filtering** | **มี (Delta Check)** | ถ้าผู้เล่นยืนนิ่ง ขยับไม่เกิน 0.04m และหันไม่เกิน 0.05 rad จะ **ระงับการส่งแพ็กเก็ตพิกัดโดยสิ้นเชิง (0 packet/s)** (`player_3d.gd: L312-317`) |
| **Server Tick Rate** | **Event-Driven (0ms Delay)** | เซิร์ฟเวอร์ทำหน้าที่เป็น Low-latency Broadcast Relay กระจายแพ็กเก็ตทันทีโดยไม่มี Fixed Loop กักขังข้อมูล |
| **Entity Interpolation** | **มี (Client Smoothing)** | ฝั่ง Client ใช้ `lerp(16.0 * delta)` และ `lerp_angle` เกลี่ยตำแหน่งผู้เล่นอื่นจาก 20 Hz ให้สมูทลื่นไหลที่ 60–144 FPS (`player_3d.gd: L168-172`) |
| **Keep-Alive Heartbeat** | **5s Ping / 35s Timeout** | Client ยิง `{ action: "ping" }` ทุกๆ 5 วินาทีตลอดเวลา เพื่อเลี้ยงท่อ Socket ไม่ให้หลุดแม้ผู้เล่นจะถูกแช่แข็ง 25–35 วินาที (`network.gd: L137-142`) |
| **Authoritative Time Sync** | **มี (1 Hz Broadcast)** | เซิร์ฟเวอร์ Broadcast อีเวนต์ `time_sync` นับถอยหลัง 165 วินาที ทุกๆ 1 วินาที เพื่อปรับเวลาในเครื่องทุกคนให้ตรงกันเป๊ะ |

### รายละเอียดเชิงลึกของการซิงค์แบบ Real-time:
1. **ทำไมต้องเป็น WebSocket สำหรับ WebGL Game?**
   * เมื่อเทียบกับ HTTP Polling หรือ Long-Polling: HTTP แบบดั้งเดิมต้องสร้าง HTTP Request Header ขนาด 600–800 ไบต์ทุกครั้ง และต้องเปิด-ปิด TCP Connection ซ้ำๆ ทำให้เกิด Latency สูงมาก
   * WebSocket ทำการ Handshake ผ่านโปรโตคอล HTTP เพียงครั้งเดียว (`HTTP 101 Switching Protocols`) หลังจากนั้นท่อ TCP จะเปิดค้างไว้แบบ Full-Duplex สองทิศทาง โดยข้อมูลแต่ละเฟรมมี Frame Header ขนาดเล็กเพียง **2–6 ไบต์** เท่านั้น ทำให้เหมาะกับการส่งข้อมูลพิกัด 20 ครั้งต่อวินาที
   * การวิ่งผ่านพอร์ต 443 ด้วยมาตรฐาน `wss://` (TLS 1.3) ทำให้การเชื่อมต่อสามารถทะลุ Proxy, Stateful Firewall และ Enterprise Gateway ของโรงเรียนหรือบริษัทได้ 100% โดยไม่ถูกบล็อกเหมือนพอร์ต UDP ทั่วไป
2. **การเกลี่ยการเคลื่อนที่ (Entity Interpolation - Client Smoothing):**
   * ข้อมูลพิกัดถูกส่งมาด้วยความถี่ 20 Hz (ทุก 50ms) หากนำพิกัดมาแสดงผลตรงๆ จะทำให้ตัวละครกระตุกเป็นจังหวะตามแพ็กเก็ต
   * ฝั่ง Client จึงใช้สมการ Exponential Smoothing ในการคำนวณตำแหน่งทุกเฟรม (60–144 FPS):
     $$\vec{P}_{\text{render}} = \text{lerp}(\vec{P}_{\text{render}}, \vec{P}_{\text{target}}, 16.0 \times \Delta t)$$
     $$\theta_{\text{render}} = \text{lerp\_angle}(\theta_{\text{render}}, \theta_{\text{target}}, 16.0 \times \Delta t)$$
     ส่งผลให้การเคลื่อนที่ของเพื่อนและศัตรูในจอภาพดูนุ่มนวลและต่อเนื่อง ไม่มีอาการ Micro-stuttering
3. **การประหยัดแบนด์วิธด้วย Stationary Threshold Filtering (Delta Check):**
   * ในการเล่นจริง ผู้เล่นมักจะมีการแอบซุ่ม หรือยืนรอจังหวะ หากส่งพิกัด 20 ครั้ง/วินาทีตลอดเวลาจะสิ้นเปลืองแบนด์วิธโดยใช่เหตุ
   * โค้ดใน `player_3d.gd` จะตรวจสอบระยะขจัด ($\Delta d$) และมุมหมุน ($\Delta \theta$):
     `if global_position.distance_to(last_sent_pos) > 0.04 or abs(rot - last_sent_rot_y) > 0.05:`
   * หากยืนนิ่ง ขยับไม่เกิน 4 เซนติเมตร และหมุนไม่เกิน 0.05 เรเดียน ตัวเกมจะไม่ส่งแพ็กเก็ตพิกัดขึ้นเซิร์ฟเวอร์เลย ลดแบนด์วิธขาขึ้นเหลือ 0 B/s ในขณะยืนนิ่ง
4. **Authoritative Event Synchronization (การซิงค์เหตุการณ์สำคัญในเกม):**
   * คำสั่งที่มีผลต่อเกมทั้งหมด (เช่น Tag ผู้เล่น, Rescue ช่วยเพื่อน, ชน Tackle, วางกล้วย, เก็บ/ใช้ไอเทม) จะต้องส่งเป็น Event ขึ้นไปขออนุมัติจากเซิร์ฟเวอร์
   * เซิร์ฟเวอร์ตรวจสอบความถูกต้อง (คำนวณ Euclidean distance $\le 4.5\text{m}$, ตรวจสถานะอมตะ, และตรวจเช็กว่าติดแช่แข็งอยู่หรือไม่) ก่อนจะกระจาย State การแช่แข็งหรือละลายกลับมาให้ทุกคนในห้องอัปเดตตรงกันแบบ Real-time

---

## 5. Connection Lifecycle & Disconnect Handling

* **Application-Level Heartbeat (Ping/Pong) & Half-Open Connection Handling (อัปเดตล่าสุด):**
  * **ปัญหา Half-Open Connection:** เมื่อผู้เล่นดึงสายแลนออก หรือสัญญาณ WiFi ดับกะทันหัน Client จะไม่มีโอกาสส่งแพ็กเก็ต `TCP FIN` หรือ `RST` มาบอก Server ทำให้ OS Kernel ของ Server ยังมองว่าท่อ TCP เปิดอยู่ (หากรอ TCP Keep-Alive ปกติของ OS อาจค้างนาน 1–2 นาที กลายเป็น "หุ่นนิ่ง" ยืนค้างในเกม)
  * **ปัญหา Edge Case เมื่อผู้เล่นถูกแช่แข็ง (Frozen State 25–35 วินาที):**
    * เมื่อผู้เล่นโดนแช่แข็ง ตัวละครจะขยับไม่ได้ ส่งผลให้ Stationary Threshold Filter หยุดส่งแพ็กเก็ตพิกัด ทำให้ท่อการเชื่อมต่อเงียบสนิท
    * หากไม่มีกลไกพิเศษ Cloudflare หรือ Reverse Proxy ของ Render.com (ซึ่งมี Idle Connection Timeout 30–60 วินาที) จะเข้าใจผิดว่าท่อเน็ตตายแล้วตัดสายทิ้งทันที
  * **กลไก Keep-Alive ฝั่ง Client (`network.gd: L71-72, L137-142`):**
    * ในระดับ Autoload ของ `network.gd` มีการรันตัวจับเวลาอิสระใน `_process(delta)`
    * ตัวเกมจะส่งข้อความระดับแอปพลิเคชัน `{ action: "ping", time: ... }` ขึ้นไปยัง Server ทุกๆ **5.0 วินาที** อย่างต่อเนื่อง ไม่ว่าตัวละครจะขยับ ยืนนิ่ง ถูกแช่แข็ง หรืออยู่ในหน้าล็อบบี้
  * **กลไกตรวจจับความเงียบและ Idle Timeout บนเซิร์ฟเวอร์ (`index.ts: L211-235`):**
    * เซิร์ฟเวอร์รันรอบตรวจทุก 10 วินาที (`HEARTBEAT_CHECK_INTERVAL_MS = 10000`)
    * ตรวจสอบเวลา `lastActiveTime` ของแต่ละ Socket หาก Client ส่งข้อความใดๆ (รวมถึง Keep-Alive Ping) จะรีเซ็ตเวลา `lastActiveTime = Date.now()` ทันที
    * เซิร์ฟเวอร์ยิง `ws.ping()` ควบคู่เพื่อกระตุ้นและรักษาท่อผ่าน Cloud Proxy
    * **Dead Socket Termination (35s Timeout):** หาก Client เงียบสนิทติดต่อกันเกิน **35 วินาที** (`SOCKET_IDLE_TIMEOUT_MS = 35000`) เซิร์ฟเวอร์จะสั่ง **`ws.terminate()`** ทันที เพื่อทำลายท่อ TCP ขยะทิ้ง
    * **ข้อพิสูจน์ว่าผู้เล่นแช่แข็ง 25–35 วินาทีจะไม่หลุด:** ในช่วง 35 วินาทีที่ผู้เล่นอยู่นิ่ง Client จะส่ง Ping ไปรีเซ็ตเวลากับเซิร์ฟเวอร์ถึง **6–7 ครั้ง** ทำให้เวลานับถอยหลังของเซิร์ฟเวอร์เริ่มนับ 0 ใหม่อยู่ตลอดเวลา การเชื่อมต่อจึงคงอยู่ 100% ปลอดภัยแน่นอน
  * **Application-Layer Latency Ping (`action: "ping"`):** เซิร์ฟเวอร์รองรับ Message `ping` ระดับแอปพลิเคชัน เพื่อส่งคืน `pong` พร้อม `serverTime` และ Client Timestamp สำหรับให้ Client นำไปคำนวณ Round-Trip Time (RTT) ได้
* **Ghost Room & Dead Socket Sweeper:**
  * ฟังก์ชัน `cleanupGhostRooms()` ทำงานทุก 4 วินาที และทำงานซ้ำทุกครั้งที่มีการดึงรายชื่อห้อง (`index.ts: L80-113`)
  * ตรวจสอบถ้า Socket ใด `readyState !== WebSocket.OPEN` จะถูกคัดออกจากห้องทันที
  * หากห้องเหลือ 0 คน จะสั่งล้าง Interval Timer ทั้งหมด และลบห้องออกจาก RAM ทันที ป้องกัน Memory Leak
* **Host Migration:**
  * หาก Host หลุด ระบบจะส่งต่อตำแหน่ง Host ให้ผู้เล่นคนถัดไปทันที พร้อมส่งอีเวนต์ `host_changed` (`index.ts: L922-930`)
* **Chaser / Tagger Disconnect Rule (อัปเดตล่าสุด):**
  * ถ้า Tagger หลุดหรือออกจากห้องจนหมด (`taggersCount === 0`) ระหว่างแข่ง $\rightarrow$ **ฝ่าย Runners จะชนะทันที** โดยระบบจะ Broadcast แจ้งเตือนและจบเกมด้วยเหตุผล `"All Taggers Disconnected"` (`index.ts: L1146-1151`)
* **Runner Disconnect Rule:**
  * ถ้า Runner คนที่ถูกแช่แข็งหลุดไป แล้วทำให้ในห้องไม่เหลือ Runner ที่รอดชีวิตอยู่เลย (`activeRunners === 0`) $\rightarrow$ **ฝ่าย Taggers จะชนะทันที** ("All Runners Frozen")
* **Reconnection & Grace Period:**
  * **ไม่มี** การ Reconnect ด้วย Session Token (หากหลุดแล้วต่อใหม่จะได้ Player ID สุ่มใหม่เสมอ)

---

## 6. Room Discovery: Public vs Private Rooms (ระบบห้องสาธารณะและห้องส่วนตัว)

| คุณสมบัติ | ห้องสาธารณะ (Public Room) | ห้องส่วนตัว (Private Room) |
| :--- | :--- | :--- |
| **การมองเห็นในรายการห้อง** | แสดงใน Public Browser และ REST API `/api/rooms` | **ถูกซ่อน 100%** (Server คัดกรองทิ้ง ไม่ส่งให้ใครเห็น) |
| **การแสดงรหัส PIN บนหน้าต่าง** | **ไม่แสดงรหัส PIN บนการ์ดห้อง** (แสดงเฉพาะชื่อห้อง, จำนวนคน, แมพ เพื่อความเป็นระเบียบและปลอดภัย) | ไม่ปรากฏในรายการห้อง ผู้เล่นต้องได้รับ PIN 6 หลักจาก Host โดยตรง |
| **วิธีการเข้าร่วม (Join Method)** | **คลิกที่การ์ดห้องเพื่อเข้าร่วมได้ทันที (One-Click Join)** โดยไม่ต้องรู้หรือพิมพ์รหัส PIN | **ต้องกรอกรหัส PIN 6 หลักเท่านั้น** ในช่อง `JOIN BY PIN` |
| **การตั้งค่า (Configuration)** | สร้างห้องโดยไม่ติ๊กช่อง `Private Room` | ติ๊กถูกที่ช่อง `Private Room` ตั้งแต่หน้าสร้าง หรือปรับในล็อบบี้ |
| **การสลับสถานะแบบ Real-time** | Host สามารถเปลี่ยนเป็น Private ได้ตลอดเวลาผ่านการตั้งค่า | Host สามารถปลดเป็น Public ได้ตลอดเวลาผ่านการตั้งค่า |

### รายละเอียดการทำงานของระบบ Public / Private ในโค้ด:

1. **การกรองข้อมูลบน Server (Server-side Filtering):**
   * ทั้งใน REST API (`GET /api/rooms`) และ WebSocket Action (`get_rooms`) เซิร์ฟเวอร์จะมีเงื่อนไขเข้มงวด:
     ```typescript
     active3DRooms.forEach((r) => {
       if (r.isPrivate) return; // กรองทิ้งทันที ไม่ส่งข้อมูลห้องส่วนตัวออกไป
       list.push({ code: r.code, name: r.name, playersCount: r.players.size, maxPlayers: r.maxPlayers, map: r.map, rounds: r.rounds, hasStarted: r.phase !== "lobby" });
     });
     ```
   * ทำให้ห้องส่วนตัวถูกซ่อนอย่างสมบูรณ์แบบที่ระดับ Server ไคลเอนต์ภายนอกไม่สามารถดักฟังหรือรู้ชื่อห้อง Private ได้เลย (`server/src/index.ts: L128-139, L425-436`)

2. **UI Architecture ของห้องสาธารณะ (อัปเดตล่าสุด):**
   * บนหน้า Lobby Browser การ์ดของ Public Room จะแสดงผลด้วย Cyber Theme Card:
     ```text
     Room 101
     Players: 1/8  |  SPACE STATION
     ```
   * **นโยบายความปลอดภัย:** ระบบ **ไม่แสดงรหัส PIN 6 หลักบนการ์ดห้องสาธารณะ** (`scripts/3d/lobby_3d.gd: L253-261`) เพื่อป้องกันความสับสนของผู้เล่น และแยกความแตกต่างอย่างชัดเจนระหว่างห้องสาธารณะ (กดเข้าได้เลย) กับห้องส่วนตัว (ต้องมี PIN)
   * เมื่อผู้เล่นคลิกที่การ์ดห้อง ระบบจะส่งคำขอ `join_room` ตรงไปยังเซิร์ฟเวอร์ทันที โดยไม่ต้องผ่านการกรอก PIN ในช่อง Join

3. **ความปลอดภัยและคณิตศาสตร์ของรหัส PIN 6 หลัก (Cryptographic Space & Anti-Brute Force):**
   * **ชุดอักขระ Base32 ไร้ความกำกวม (No Ambiguous Characters):**
     * ตัวเกมใช้ตัวอักษร 32 ตัว: `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (`scripts/3d/lobby_3d.gd: L4`, `server/src/index.ts: L20`)
     * **ตัดตัวอักษรที่สับสนง่ายออกทั้งหมด:** ไม่มีเลข `0` กับอักษร `O`, ไม่มีเลข `1` กับอักษร `I` ทำให้ผู้เล่นส่งต่อรหัสให้เพื่อนพิมพ์ตามได้ง่าย ไม่ผิดพลาด
   * **ขนาด Key Space มหาศาล:**
     $$N = 32^6 = 1,073,741,824 \text{ รูปแบบ (มากกว่า 1.07 พันล้านชุด)}$$
   * **ความน่าจะเป็นในการสุ่มเดา (Brute Force Probability):**
     * หากเซิร์ฟเวอร์มีห้อง Private เปิดอยู่เต็มความจุ 50 ห้องพร้อมกัน ความน่าจะเป็นที่ผู้ไม่หวังดีจะสุ่มเดาถูกใน 1 ครั้งคือ:
       $$P = \frac{50}{1,073,741,824} \approx 4.65 \times 10^{-8} \quad (0.0000046\%)$$
   * **ระบบป้องกัน Anti-Brute Force สองชั้นบน Server (`index.ts: L441-455`):**
     * **ชั้นที่ 1 (Rate Limiting):** ตรวจสอบระยะเวลาระหว่างคำขอ Join หากส่งถี่กว่า 1 ครั้งต่อ 600ms จะถูกปฏิเสธทันที
     * **ชั้นที่ 2 (Lockout Penalty):** หากไคลเอนต์ใส่รหัสผิดสะสมครบ 5 ครั้ง เซิร์ฟเวอร์จะทำการระงับการเชื่อมต่อ (Lockout) ทันทีเป็นเวลา 5 วินาที
     * **บทวิเคราะห์ความปลอดภัย:** ด้วยการจำกัดอัตรานี้ แฮกเกอร์จะลองรหัสได้ไม่เกิน $\approx 1$ ครั้งต่อวินาที การจะสุ่มเดาจนเจอห้อง Private ต้องใช้เวลาเฉลี่ยถึง **34 ปี** จึงปลอดภัยจากการเดารหัส 100%

4. **การแชร์รหัสห้องส่วนตัว (PIN Sharing):**
   * เมื่อ Host สร้างห้องแบบ Private ในหน้าห้องรอ (Waiting Room) จะมีกล่องแสดงรหัส PIN 6 หลักตัวโต พร้อมปุ่ม **"COPY"** (`scripts/3d/lobby_3d.gd: L634-639`)
   * เมื่อกดปุ่ม ระบบจะคัดลอกรหัสเข้า System Clipboard ของผู้เล่นทันที เพื่อนำไปส่งให้เพื่อนทาง Discord, Line หรือ Messenger

5. **การสลับสถานะแบบ Real-time ในห้อง (Dynamic Privacy Toggle):**
   * Host สามารถคลิกสลับ Checkbox `Private Room` ได้สดๆ ภายในล็อบบี้
   * Client จะส่งคำสั่ง `update_settings` ไปยัง Server (`network.gd: L395-403`)
   * Server อัปเดต `r.isPrivate` และ Broadcast อีเวนต์ `settings_updated` ให้ทุกคนในห้องรับทราบ
   * เมื่อห้องถูกสลับเป็น Private ห้องนั้นจะถูกดึงออกจาก Public Browser ของผู้เล่นคนอื่นทันทีในรอบรีเฟรชถัดไป

6. **ระบบดึงรายชื่อห้องแบบ Dual-Channel และ Auto-Fetch:**
   * **Auto-Fetch อัตโนมัติ:** เมื่อผู้เล่นเข้าหน้า Lobby Browser หรือเชื่อมต่อ Socket สำเร็จ ตัวเกมจะยิงคำขอขอรายชื่อห้องอัตโนมัติทันที ไม่จำเป็นต้องคอยกดปุ่ม Refresh เอง
   * **Dual-Channel Architecture:** เมื่อกดปุ่ม Refresh ตัวเกมจะยิง Action `get_rooms` ผ่าน WebSocket เป็นช่องทางหลัก (ความเร็วระดับมิลลิวินาที) พร้อมยิง HTTP REST `/api/rooms` เป็นช่องทางสำรอง
   * **Server-side Active Sweeping:** ทุกครั้งที่มีการขอรายชื่อห้อง เซิร์ฟเวอร์จะรัน `cleanupGhostRooms()` ทันทีเพื่อกวาดล้างห้องร้าง 0 คนทิ้ง ทำให้รายชื่อห้องที่แสดงผลสดใหม่เสมอและไม่มีห้องผีตกค้าง

---

## 7. Capacity, Scalability & Bandwidth Estimation

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

## 8. Security & Input Validation Analysis

* **ระบบป้องกันและ Validation ที่ทำงานอยู่บน Server:**
  * **ชื่อผู้เล่น (Player Name):** แปลงเป็น String, ตัดช่องว่าง และจำกัดความยาวไม่เกิน 16 ตัวอักษร (`index.ts: L278`)
  * **จำนวนผู้เล่นและรอบการแข่ง:** Clamp ตัวเลขให้อยู่ในช่วง 4–8 คน และ 1–5 รอบ (`index.ts: L317-318`)
  * **รหัสห้อง (Room Code):** แปลงเป็นตัวพิมพ์ใหญ่ และจำกัดเฉพาะอักษรไร้ความกำกวม 32 ตัว (`CHARS`)
  * **การเริ่มเกม:** บังคับตรวจสอบสถานะ Ready ของผู้เล่นทุกคนก่อนเริ่ม (`index.ts: L523-534`)
  * **Anti-Brute Force Room Code (ป้องกันการยิงเดารหัสห้อง):** จำกัดความถี่การขอ Join ไม่เกิน 1 ครั้งต่อ 600ms และหากใส่รหัสผิดติดต่อกัน 5 ครั้ง จะทำการ Lockout ระงับการ Join ชั่วคราว 5 วินาทีทันที (`index.ts: L405-425`)
  * **Sanitization พิกัดตำแหน่ง (Anti-Glitch / Anti-Teleport):** ปฏิเสธค่า `NaN`, `Infinity` และตรวจสอบ Bounding Box หากพิกัดหลุดออกนอกแมพ ($|x| > 40$ หรือ $|z| > 40$) จะถูกทิ้งทันที (`index.ts: L650-655`)
  * **Anti-Global Freeze (ตรวจสอบระยะห่างการ Tag / Rescue):** เซิร์ฟเวอร์คำนวณ Euclidean distance ($\text{dist} \le 4.5\text{m}$) ป้องกันการส่งคำสั่งแช่แข็งหรือช่วยเพื่อนข้ามแผนที่ (`index.ts: L673-678, L705-710`)
  * **Anti-Spam Tackle (ป้องกันการสแปมดาเมจใส่แท็กเกอร์):** บังคับ Cooldown ฝั่งเซิร์ฟเวอร์ 2.0 วินาที พร้อมตรวจระยะห่าง ($\text{dist} \le 5.0\text{m}$) ก่อนหัก HP แท็กเกอร์ (`index.ts: L829-842`)
* **จุดที่ควรทราบเพิ่มเติม (Architecture Limitations):**
  1. **ไม่มี Full Server-side Physics Engine:** ยังคงให้ Client คำนวณการเดินและการชนสิ่งกีดขวางเองเพื่อประหยัด CPU
  2. **ไม่มี Speed Hack Detection แบบ Real-time:** ยังไม่ได้นำ $\Delta s / \Delta t$ มาคำนวณความเร็วเฉลี่ยทุกเฟรม
  3. **State เก็บใน In-Memory RAM:** หากเซิร์ฟเวอร์รีสตาร์ตข้อมูลห้องจะถูกรีเซ็ต (ไม่มี Persistent Database)

---

## 9. Deployment Configuration
* **Service Provider:** Render.com
* **Configuration File:** `render.yaml` อยู่ที่ Root Directory
* **Build Command:** `npm install && npm run build`
* **Start Command:** `npm run start`
* **Static Client Serving:** ให้ Express โฮสต์ไฟล์ Web Build ของ Godot (`index.html`, `index.pck`, `index.wasm`) จากโฟลเดอร์ `server/public` พร้อมตั้งค่า Header `Cross-Origin-Opener-Policy: same-origin` และ `Cross-Origin-Embedder-Policy: require-corp` สำหรับ WebAssembly SharedArrayBuffer

---

## 10. Computer Networking Oral Defense & Theory Reference (คลังความรู้การสอบปากเปล่าวิศวกรรมเครือข่าย 30 ข้อ)

### หมวด 1: ความหน่วงและเวลาแฝง (Latency)
1. **องค์ประกอบของ Nodal Delay ($d_{\text{nodal}} = d_{\text{proc}} + d_{\text{queue}} + d_{\text{trans}} + d_{\text{prop}}$):**
   * $d_{\text{proc}}$ (Processing Delay): เวลาตรวจ Header, Checksum, Route lookup ในเราเตอร์และเซิร์ฟเวอร์ ($< 1\text{ ms}$)
   * $d_{\text{queue}}$ (Queuing Delay): เวลาจอดรอคิวใน Output Buffer ของเราเตอร์ แปรผันตาม Traffic Intensity ($La/R$)
   * $d_{\text{trans}}$ (Transmission Delay): เวลาผลักบิตลงสาย คำนวณจาก $L/R$
   * $d_{\text{prop}}$ (Propagation Delay): เวลาคลื่นแสงเดินทางตามระยะทาง $d/s$
   * **ส่วนที่ลดไม่ได้ตามกฎฟิสิกส์:** $d_{\text{prop}}$ เพราะความเร็วแสงในสายไฟเบอร์มีขีดจำกัดสูงสุดที่ $\approx 200,000\text{ km/s}$ ($c/n, n \approx 1.47$)
2. **RTT vs One-Way Delay:**
   * One-way delay คือเวลาเดินทางขาเดียว ($A \rightarrow B$)
   * RTT คือเวลาไป-กลับรวมการประมวลผล ($A \rightarrow B \rightarrow A$)
   * Ping วัด One-way ตรงๆ ไม่ได้เพราะ: (1) ปัญหา Clock Synchronization ข้ามเครื่อง และ (2) Asymmetric Routing (ขาไปกับขากลับวิ่งคนละเส้นทาง)
3. **โจทย์คำนวณ $d_{\text{trans}}$ vs $d_{\text{prop}}$:**
   * แพ็กเก็ต $150\text{ B} = 1,200\text{ bits}$, ลิงก์ $10\text{ Mbps}$, ระยะ $3,000\text{ km}$:
     * $d_{\text{trans}} = 1,200 / 10,000,000 = \mathbf{0.12\text{ ms}}$
     * $d_{\text{prop}} = 3,000\text{ km} / 200,000\text{ km/s} = \mathbf{15.0\text{ ms}}$
     * **Propagation Delay (15 ms) เด่นกว่า Transmission Delay (0.12 ms) ถึง 125 เท่า!**
4. **ทำไมอัปเกรดเน็ต 100M เป็น 1G ปิงแทบไม่ลด:**
   * การอัปเกรดแบนด์วิธลดเฉพาะ $d_{\text{trans}}$ (ประหยัดได้แค่ $0.01\text{ ms}$) แต่ปิงถูกครอบงำด้วย $d_{\text{prop}}$ (ระยะทางสายไฟเบอร์) ซึ่งไม่เปลี่ยนแปลง
5. **Queuing Delay & Bufferbloat:**
   * เกิดที่ Output Buffer ของเราเตอร์ที่บ้านและ ISP Gateway
   * Bufferbloat คือการใส่บัฟเฟอร์ขนาดใหญ่เกินไปเพื่อเลี่ยง Packet Loss เมื่อผู้ใช้โหลดไฟล์เต็มท่อ แพ็กเก็ตใหญ่จะอัดเต็มคิว ทำให้แพ็กเก็ตเล็กของเกมต้องต่อคิวยาว ปิงจึงพุ่งทะลุ 400ms

### หมวด 2: ความแปรปรวนและการสูญหายของแพ็กเก็ต (Jitter & Packet Loss)
6. **Jitter:**
   * ความแปรปรวนของเวลาที่แพ็กเก็ตเดินทางมาถึง (Inter-arrival time variation) เกิดจาก Queuing Delay ผันผวน, การส่งซ้ำบน Wi-Fi, และ Dynamic Routing วัดด้วย `iperf3 -u` หรือสมการ RFC 3550
7. **สาเหตุของ Packet Loss:**
   * Buffer Overflow ในเราเตอร์ (สาเหตุหลัก) และ Bit Error จากสัญญาณรบกวนใน Wi-Fi ตรวจพบใน TCP ด้วย Retransmission Timeout (RTO) และ Triple Duplicate ACKs
8. **TCP กับ Packet Loss และ Head-of-Line (HoL) Blocking:**
   * TCP ซ่อมแพ็กเก็ตด้วย Fast Retransmit หรือ RTO
   * แพ็กเก็ตที่มาถึงทีหลังจะถูกกักไว้ใน Receive Buffer ของ Kernel ไม่ยอมส่งขึ้นแอปพลิเคชันจนกว่าตัวที่หายจะถูกส่งซ่อมมาถึง ผู้ใช้จะเห็นเกมหยุดนิ่งชั่วขณะแล้ววาร์ปพุ่งไปข้างหน้า
9. **ทำไม Loss 2% ทำให้ TCP Throughput ตกหนัก:**
   * เพราะ TCP ถือว่า Loss คือสัญญาณเตือน Congestion จึงสั่งตัด Congestion Window (cwnd) ลงครึ่งหนึ่งทันที (Multiplicative Decrease) ตามสมการ Mathis Throughput $\propto \frac{1}{\text{RTT}\sqrt{p}}$ ค่า cwnd จึงไม่สามารถโตได้
10. **ทำไมค่าเฉลี่ยปิงบอกอะไรไม่ได้:**
    * ค่าเฉลี่ยเกลี่ย Spike ให้ดูเรียบ (เช่น 99 แพ็กเก็ต 40ms + 1 แพ็กเก็ต 400ms = เฉลี่ย 43.6ms แต่ผู้ใช้กระตุกไปแล้ว) ต้องดู Percentile ($P_{95}, P_{99}$), Max Latency และ Jitter แทน

### หมวด 3: แบนด์วิธและ Throughput (พร้อมโจทย์คำนวณ)
11. **Bandwidth vs Throughput vs Goodput:**
    * Bandwidth = ขีดจำกัดทางทฤษฎีสูงสุด
    * Throughput = อัตราข้อมูลจริงรวม Header และ Retransmit
    * Goodput = เฉพาะ Application Payload ที่ส่งสำเร็จ ($\text{Goodput} < \text{Throughput} \le \text{Bandwidth}$)
12. **Small Packet Problem & Header Overhead:**
    * Payload 100 ไบต์ + Ethernet (18B) + IPv4 (20B) + TCP (20B) + TLS 1.3 (21B) + WebSocket (6B) $\approx 185\text{ ไบต์}$
    * สัดส่วน Header สูงถึง 46%–60% สิ้นเปลืองเมื่อส่งถี่
13. **โจทย์คำนวณที่ 1 (แบนด์วิธต่อผู้เล่น 1 คน):**
    * ผู้เล่น 1 คนส่ง 100B 20 Hz, รับจาก 7 คน คนละ 20 Hz (รวมรับ 140 msg/s):
      * ไม่รวม overhead: Uplink = $2\text{ KB/s}$ (16 Kbps), Downlink = $14\text{ KB/s}$ (112 Kbps)
      * รวม overhead 50B (แพ็กเก็ต 150B): Uplink = $3\text{ KB/s}$ (24 Kbps), Downlink = $21\text{ KB/s}$ (168 Kbps)
      * สัดส่วน Overhead = $50/150 = \mathbf{33.33\%}$ (เพิ่มขึ้น +50% ของ Payload)
14. **โจทย์คำนวณที่ 2 (ภาระเซิร์ฟเวอร์ที่ 400 ผู้ใช้ 50 ห้อง):**
    * ขาเข้า: $400 \times 20 = \mathbf{8,000\text{ msg/s}}$
    * ขาออก (Fan-out $\times 7$): $8,000 \times 7 = \mathbf{56,000\text{ msg/s}}$
    * แบนด์วิธขาออก (ที่ 150B รวม overhead): $56,000 \times 150\text{ B} = 8.4\text{ MB/s} = \mathbf{67.2\text{ Mbps}}$
    * สมการเติบโตต่อห้อง: $R_{\text{out}} = N(N-1)f \approx \mathbf{O(N^2)}$
    * **ทำไม CPU ตันก่อน Bandwidth:** ท่อ Cloud รองรับได้ 1 Gbps (ใช้ไปแค่ 6.7%) แต่ Node.js เป็น Single Thread การส่ง 56,000 msg/s ทำให้ CPU แตะ 100% จนเกิด Event Loop Starvation
15. **5 ทางเลือกในการลด Bandwidth 50%:**
    * ลดความถี่ (20 $\rightarrow$ 10 Hz), เปลี่ยนเป็น Binary (Protobuf/MsgPack), Threshold Filtering (หยุดส่งตอนยืนนิ่ง), Delta Compression, Message Batching
16. **Message Batching Trade-off:**
    * ลด Overhead เพราะแชร์ Header ชุดเดียว แต่เพิ่ม Latency เพราะแพ็กเก็ตแรกต้องจอดรอในคิวรวมก้อน

### หมวด 4: เจาะลึกกลไก TCP
17. **Handshake RTT Budget:**
    * TCP 3-Way Handshake = 1 RTT, TLS 1.3 = 1 RTT รวมก่อนส่งข้อมูลจริงได้ = 2 RTTs
18. **Flow Control vs Congestion Control:**
    * Flow Control ป้องกัน Receiver Buffer ล้น (ควบคุมด้วย rwnd), Congestion Control ป้องกัน Network Link ล้น (ควบคุมด้วย cwnd)
19. **Slow Start & cwnd:**
    * เริ่มจาก cwnd ต่ำ แล้วโตแบบ Exponential ($2^n$) ทุก 1 RTT การเชื่อมต่อใหม่จึงส่งได้ช้ากว่าการเชื่อมต่อเก่าที่ cwnd ขยายเต็ม BDP แล้ว
20. **Nagle's Algorithm + Delayed ACK = Latency Trap:**
    * Nagle รอ ACK แต่ Delayed ACK รอข้อมูล ทำให้ข้อความเล็กหน่วงค้าง 40–200ms ต้องแก้ด้วย `TCP_NODELAY`
21. **Half-Open Connection & Keepalive Lessons Learned:**
    * การดึงสายแลนไม่ส่ง FIN/RST ท่อ TCP จึงค้างเงียบ
    * **บทเรียนจากระบบจริง:** การใช้ `ws.ping()` 5s ตัดเร็วเกินไปจะติดปัญหา Cloud Reverse Proxy บล็อก Opcode 0x9/0xA ทำให้เตะผู้ใช้มั่ว จึงปรับมาใช้ **Client 5s Keep-Alive Ping + Server 35s Idle Timeout** เป็นเกณฑ์ที่เสถียรที่สุด

### หมวด 5: โครงสร้างเส้นทางและการนำส่งข้อมูล
22. **Path of Packet & Traceroute:**
    * เดินทางผ่าน Wi-Fi $\rightarrow$ Home Router $\rightarrow$ ISP Gateway $\rightarrow$ Backbone/IXP $\rightarrow$ Cloud Edge Proxy $\rightarrow$ Server
    * Traceroute วัด RTT ราย Hop เพื่อหาจุดคอขวด
23. **TTL (Time-To-Live):**
    * ป้องกันแพ็กเก็ตวนลูป เมื่อ TTL=0 เราเตอร์ทิ้งแพ็กเก็ตแล้วส่ง ICMP Time Exceeded กลับมา Traceroute ใช้หลักการนี้โดยส่ง TTL เริ่มต้นที่ 1, 2, 3...
24. **NAT Traversal & P2P Difficulty:**
    * NAT สลับ Private IP เป็น Public IP ในตาราง NAT Table ทำให้คนนอกต่อเข้ามาหาเครื่องเราไม่ได้ P2P จึงต้องใช้ STUN/TURN หรือ Hole Punching
25. **DNS Resolution Impact:**
    * ใช้เวลา 10–100ms มีผลเฉพาะตอนเริ่มต่อครั้งแรกครั้งเดียว เพราะหลังจากนั้นต่อตรงผ่าน IP เดิมตลอด
26. **MTU & Fragmentation:**
    * MTU ปกติคือ 1,500 ไบต์ ถ้าใหญ่กว่าจะเกิด IP Fragmentation แต่แพ็กเก็ตเกมมีขนาดเพียง 150–200 ไบต์ จึงไม่เจอปัญหานี้แน่นอน

### หมวด 6: การวัดผล ความปลอดภัย และสถาปัตยกรรม
27. **เครื่องมือวัดเครือข่าย:**
    * `ping` (RTT/Loss รวม), `traceroute/mtr` (หา Hop ที่ช้า), `Wireshark` (ดู TCP Flags/Retransmits), `iperf3` (วัด Max Throughput/Jitter), `tc netem` (ฉีด Delay/Loss จำลอง)
28. **การจำลองสภาวะเครือข่ายแย่ (ปิง 300ms, Loss 5%):**
    * ใช้ `tc qdisc add dev eth0 root netem delay 300ms 20ms loss 5%` วัด TCP Retransmit Rate, Event Loop Lag, และ Entity Interpolation
29. **Wireshark กับ TLS Traffic:**
    * สิ่งที่เห็น: Handshake, SNI Domain, IP/Port, Packet Size, Packet Timing
    * สิ่งที่ไม่เห็น: Application Payload (พิกัดและคำสั่งใน JSON ถูกเข้ารหัสเป็น Ciphertext)
30. **การปรับแต่งที่ระดับแอปพลิเคชัน และการเปลี่ยนเป็นแอปแชตกลุ่ม:**
    * ปรับ `TCP_NODELAY` + Client-Side Prediction + Entity Interpolation + Threshold Filtering
    * หากเปลี่ยนเป็นแอปแชต: ใช้ WebSocket และ Heartbeat เดิมได้ แต่ต้องเปลี่ยนเป็น Event-Driven (ไม่ส่ง 20 Hz), เพิ่ม Database เก็บ Message History, และมี Message Delivery ACKs

### หมวด 7: คำถามเจาะลึกระบบห้อง Public/Private และการซิงค์ Real-time ผ่าน WebSocket
31. **การออกแบบความปลอดภัยของห้อง Public vs Private และทำไมห้อง Public จึงไม่ควรโชว์ PIN 6 หลัก?**
    * **UX & Functional Separation:** ห้อง Public ออกแบบมาเพื่อการเข้าเล่นแบบเปิด (One-Click Join) การแสดงรหัส PIN บนการ์ดห้อง Public นอกจากจะซ้ำซ้อนแล้ว ยังสร้างความสับสนให้ผู้เล่นคิดว่าต้องจำรหัสไปกรอกในช่อง "JOIN BY PIN" การซ่อน PIN บนการ์ดห้อง Public ทำให้ผู้ใช้แยกแยะชัดเจนว่า การกดการ์ดคือเข้าห้องสาธารณะ ส่วนการใช้ PIN มีไว้สำหรับห้องส่วนตัว (Private Room) เท่านั้น
    * **Server-side Security:** ห้อง Private ถูกตัดทิ้งตั้งแต่ระดับ Data Layer บนเซิร์ฟเวอร์ (`if (r.isPrivate) return;`) จึงไม่มีข้อมูลรั่วไหลไปใน Broadcast แพ็กเก็ต ผู้เล่นภายนอกไม่สามารถใช้ DevTools หรือ Wireshark ดักจับชื่อหรือพิกัดของห้อง Private ได้
32. **Cryptographic Key Space ของ Room PIN 6 หลัก และการป้องกันการเดารหัส (Brute-Force Protection)?**
    * **Base32 Alphabet (ไร้ความสับสน):** ใช้ตัวอักษร 32 ตัวตัด `0, O, 1, I` ออกทั้งหมด เพื่อตัดปัญหา Human Error เวลาพิมพ์ตาม
    * **ขนาด Key Space:** $32^6 = 1,073,741,824$ รูปแบบ (มากกว่า 1.07 พันล้านชุด)
    * **ความน่าจะเป็นในการเดาถูก:** หากมีห้อง Private เปิดอยู่ 50 ห้อง โอกาสสุ่มเดาถูกใน 1 ครั้งคือเพียง $\approx 4.65 \times 10^{-8}$ ($0.0000046\%$)
    * **Anti-Brute Force สองชั้นบนเซิร์ฟเวอร์:** (1) Throttling ไม่ให้ส่งคำขอบ่อยเกิน 600ms ต่อครั้ง และ (2) Lockout ระงับการ Join 5 วินาทีทันทีที่ใส่รหัสผิดครบ 5 ครั้ง ทำให้ในทางปฏิบัติไม่สามารถใช้สคริปต์ยิง Brute-force ได้ (ต้องใช้เวลาเฉลี่ยถึง 34 ปี)
33. **Edge Case ผู้เล่นถูกแช่แข็ง 25–35 วินาที: ทำไมการซิงค์แบบ Delta Threshold ถึงเกือบทำให้หลุด และแก้ด้วย WebSocket Ping-Pong อย่างไร?**
    * **ปัญหาที่เกิดขึ้น:** เพื่อประหยัดแบนด์วิธ ตัวเกมมี Delta Threshold Filter สั่งหยุดส่งพิกัดเมื่อยืนนิ่ง เมื่อผู้เล่นถูกแช่แข็ง ($25–35\text{s}$) ตัวละครขยับไม่ได้ แพ็กเก็ตพิกัดจึงเป็น 0 ท่อ WebSocket เงียบสนิท ทำให้ Reverse Proxy ของ Cloud (Render/Cloudflare ที่มี Idle Timeout 30–60s) และ Idle Sweeper ของเซิร์ฟเวอร์มองว่าเป็น Dead Socket และตัดสายทิ้งทันที
    * **สถาปัตยกรรมแก้ไข:** ฝั่ง Client มีลูป Heartbeat แยกอิสระในระดับ Autoload ส่ง `{ action: "ping" }` ทุกๆ **5 วินาที** เสมอ แม้ตัวละครจะถูกแช่แข็ง ทำให้เซิร์ฟเวอร์และ Reverse Proxy ได้รับทราฟฟิกและรีเซ็ตตัวจับเวลาตลอดเวลา การเชื่อมต่อจึงปลอดภัย 100% ไม่หลุดแน่นอน
34. **ความแตกต่างระหว่าง Entity Interpolation กับ Client Prediction ในการซิงค์แบบ Real-time?**
    * **Entity Interpolation (ทำงานที่เครื่องรับ):** ใช้กับตัวละครของผู้เล่นคนอื่น (Remote Players) เนื่องจากตำแหน่งส่งมาด้วยความถี่ 20 Hz (ทุก 50ms) Client จะใช้ Exponential Lerp (`lerp(16.0 * delta)`) คำนวณจุดกึ่งกลางระหว่างพิกัดเก่าและพิกัดใหม่ทุกๆ เฟรมของการเรนเดอร์ (60–144 FPS) เพื่อให้ภาพการเคลื่อนที่นุ่มนวล
    * **Client Prediction (ทำงานที่เครื่องส่ง):** ใช้กับตัวละครของผู้เล่นเอง (Local Player) โดยประมวลผลการกดปุ่มเดินและฟิสิกส์ทันทีในเครื่องโดยไม่ต้องรอเซิร์ฟเวอร์ตอบรับ เพื่อตัด Input Lag ให้การบังคับรู้สึกตอบสนองทันที (Responsive)
