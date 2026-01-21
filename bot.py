import os
import json
import io
import aiohttp
import datetime
import discord as dc
from datetime import timedelta
from discord.ext import commands, tasks
from discord import app_commands
from discord import ui, Interaction, ButtonStyle, Embed
from PIL import Image, ImageDraw, ImageFont
from typing import Literal

# Import backup manager for automatic GitHub backups
try:
    from backup_manager import init_backup_manager, backup_to_github
    BACKUP_ENABLED = True
except ImportError:
    print("[WARNING] backup_manager.py not found, GitHub backups disabled")
    BACKUP_ENABLED = False
    backup_to_github = lambda *args, **kwargs: None  # No-op function


WARN_FILE = "warns.json"

if os.path.exists(WARN_FILE):
    with open(WARN_FILE, "r") as f:
        warns = json.load(f)
else:
    warns = {}

def save_warns():
    with open(WARN_FILE, "w") as f:
        json.dump(warns, f, indent=4)

TICKET_PANEL_CHANNEL_ID = 1434769506798010480
TICKET_LOG_CHANNEL_ID = 1452681875029102624
STAFF_ROLE_ID = 1434818807368519755
HELPER_ROLE_ID = 1457350924958695455
TICKET_CATEGORY_ID = 1434818160577609840
TICKET2_CATEGORY_ID = 1463498104257904721

TICKET_CATEGORY_ID_MIDMAN = 1462046059143630984
TICKET_PANEL_CHANNEL_ID_MIDMAN = 1462045378324205590
MIDMAN_ROLE_ID = 1462063370189537280

TICKET_PANEL_CHANNEL_ID_X8 = 1461688996081176628
TICKET_CATEGORY_ID_X8 = 1461709088118407412

UNVERIFIED_ROLE_ID = 1434816903439843359
MEMBER_ROLE_ID = 1434816903439843359
WL_ROLE_ID = 1452500424551567360  # Whitelist role

VORA_BLUE = 0x3498db
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
TICKET_DATA_FILE = os.path.join(BASE_DIR, "tickets.json")
MIDMAN_TICKET_FILE = os.path.join(BASE_DIR, "midmanticket.json")
X8_TICKET_FILE = os.path.join(BASE_DIR, "x8ticket.json")
CLAIMS_FILE = os.path.join(BASE_DIR, "claims.json")
SALES_FILE = os.path.join(BASE_DIR, "sales.json")

# Initialize GitHub backup manager
if BACKUP_ENABLED:
    try:
        # Load GitHub config
        github_config_file = os.path.join(BASE_DIR, "github_config.json")
        if os.path.exists(github_config_file):
            with open(github_config_file, "r") as f:
                github_config = json.load(f)
                repo_url = github_config.get("github", {}).get("repository_url", "")
                auth_token = github_config.get("github", {}).get("auth_token", "")
                
                if repo_url and auth_token:
                    # Initialize with token (new system requires all 3 params)
                    backup_manager = init_backup_manager(
                        repo_path=BASE_DIR,
                        remote_url=repo_url,
                        auth_token=auth_token
                    )
                    print("[BACKUP] ✓ GitHub backup system initialized")
                    print("[BACKUP] ✓ Queue-based batching enabled")
                    print("[BACKUP] ✓ Thread-safe locking active")
                    print(f"[BACKUP] ✓ Remote: {repo_url.replace(auth_token, '***')}")
                else:
                    print("[BACKUP] ✗ Missing repository_url or auth_token in config")
                    print("[BACKUP] ✗ Please edit github_config.json")
                    BACKUP_ENABLED = False
        else:
            print("[BACKUP] ✗ github_config.json not found")
            BACKUP_ENABLED = False
    except Exception as e:
        print(f"[BACKUP] ✗ Failed to initialize: {e}")
        import traceback
        traceback.print_exc()
        BACKUP_ENABLED = False

# ---------------------------
# LOAD / SAVE TICKETS
# ---------------------------
if not os.path.exists(TICKET_DATA_FILE):
    with open(TICKET_DATA_FILE, "w") as f:
        json.dump({"counter": 0, "tickets": {}}, f, indent=4)
    active_tickets = {}
    ticket_count = 0
else:
    with open(TICKET_DATA_FILE, "r") as f:
        try:
            data = json.load(f)
            # Support old format (just dict of tickets) and new format (with counter)
            if "tickets" in data:
                active_tickets = {int(k): v for k, v in data["tickets"].items()}
                ticket_count = data.get("counter", 0)
            else:
                # Old format - just a dict of user_id: channel_id
                active_tickets = {int(k): v for k, v in data.items()}
                ticket_count = 0
        except json.JSONDecodeError:
            active_tickets = {}
            ticket_count = 0

def save_tickets():
    with open(TICKET_DATA_FILE, "w") as f:
        json.dump({
            "counter": ticket_count,
            "tickets": {str(k): v for k, v in active_tickets.items()}
        }, f, indent=4)

# ---------------------------
# LOAD / SAVE MIDMAN TICKETS
# ---------------------------
if not os.path.exists(MIDMAN_TICKET_FILE):
    with open(MIDMAN_TICKET_FILE, "w") as f:
        json.dump({"counter": 0, "tickets": {}}, f, indent=4)
    midman_tickets = {}
    midman_ticket_count = 0
else:
    with open(MIDMAN_TICKET_FILE, "r") as f:
        try:
            data = json.load(f)
            if "tickets" in data:
                midman_tickets = {int(k): v for k, v in data["tickets"].items()}
                midman_ticket_count = data.get("counter", 0)
            else:
                midman_tickets = {int(k): v for k, v in data.items()}
                midman_ticket_count = 0
        except json.JSONDecodeError:
            midman_tickets = {}
            midman_ticket_count = 0

def save_midman_tickets():
    with open(MIDMAN_TICKET_FILE, "w") as f:
        json.dump({
            "counter": midman_ticket_count,
            "tickets": {str(k): v for k, v in midman_tickets.items()}
        }, f, indent=4)

def add_midman_ticket(user_id, channel_id):
    midman_tickets[user_id] = channel_id
    save_midman_tickets()

def remove_midman_ticket(user_id):
    if user_id in midman_tickets:
        del midman_tickets[user_id]
        save_midman_tickets()

def increment_midman_ticket_counter():
    global midman_ticket_count
    midman_ticket_count += 1
    save_midman_tickets()
    return midman_ticket_count

# ---------------------------
# LOAD / SAVE X8 TICKETS
# ---------------------------
if not os.path.exists(X8_TICKET_FILE):
    with open(X8_TICKET_FILE, "w") as f:
        json.dump({"counter": 0, "tickets": {}}, f, indent=4)
    x8_tickets = {}
    x8_ticket_count = 0
else:
    with open(X8_TICKET_FILE, "r") as f:
        try:
            data = json.load(f)
            if "tickets" in data:
                x8_tickets = {int(k): v for k, v in data["tickets"].items()}
                x8_ticket_count = data.get("counter", 0)
            else:
                x8_tickets = {int(k): v for k, v in data.items()}
                x8_ticket_count = 0
        except json.JSONDecodeError:
            x8_tickets = {}
            x8_ticket_count = 0

def save_x8_tickets():
    with open(X8_TICKET_FILE, "w") as f:
        json.dump({
            "counter": x8_ticket_count,
            "tickets": {str(k): v for k, v in x8_tickets.items()}
        }, f, indent=4)

def add_x8_ticket(user_id, channel_id):
    x8_tickets[user_id] = channel_id
    save_x8_tickets()

def remove_x8_ticket(user_id):
    if user_id in x8_tickets:
        del x8_tickets[user_id]
        save_x8_tickets()

def increment_x8_ticket_counter():
    global x8_ticket_count
    x8_ticket_count += 1
    save_x8_tickets()
    return x8_ticket_count

# ---------------------------
# LOAD / SAVE CLAIMS
# ---------------------------
if not os.path.exists(CLAIMS_FILE):
    with open(CLAIMS_FILE, "w") as f:
        json.dump({}, f, indent=4)
    ticket_claims = {}
else:
    with open(CLAIMS_FILE, "r") as f:
        try:
            data = json.load(f)
            ticket_claims = {int(k): int(v) for k, v in data.items()}
        except json.JSONDecodeError:
            ticket_claims = {}

def save_claims():
    with open(CLAIMS_FILE, "w") as f:
        json.dump({str(k): str(v) for k, v in ticket_claims.items()}, f, indent=4)
    # Auto-backup to GitHub
    if BACKUP_ENABLED:
        backup_to_github(["claims.json"], async_mode=True)

def add_claim(channel_id, staff_id):
    ticket_claims[channel_id] = staff_id
    save_claims()

def remove_claim(channel_id):
    if channel_id in ticket_claims:
        del ticket_claims[channel_id]
        save_claims()

def get_claim(channel_id):
    return ticket_claims.get(channel_id)

# ---------------------------
# LOAD / SAVE DONE TICKETS (to prevent double-done)
# ---------------------------
DONE_TICKETS_FILE = os.path.join(BASE_DIR, "done_tickets.json")

if not os.path.exists(DONE_TICKETS_FILE):
    with open(DONE_TICKETS_FILE, "w") as f:
        json.dump([], f, indent=4)
    done_tickets = []
else:
    with open(DONE_TICKETS_FILE, "r") as f:
        try:
            done_tickets = json.load(f)
        except json.JSONDecodeError:
            done_tickets = []

def save_done_tickets():
    with open(DONE_TICKETS_FILE, "w") as f:
        json.dump(done_tickets, f, indent=4)
    # Auto-backup to GitHub
    if BACKUP_ENABLED:
        backup_to_github(["done_tickets.json"], async_mode=True)

def mark_ticket_done(channel_id):
    """Mark a ticket as done"""
    if channel_id not in done_tickets:
        done_tickets.append(channel_id)
        save_done_tickets()

def is_ticket_done(channel_id):
    """Check if ticket is already marked as done"""
    return channel_id in done_tickets

def remove_done_ticket(channel_id):
    """Remove ticket from done list when closed"""
    if channel_id in done_tickets:
        done_tickets.remove(channel_id)
        save_done_tickets()

# ---------------------------
# LOAD / SAVE COOLDOWNS (Hybrid: 20min reset OR 2hour cooldown)
# ---------------------------
COOLDOWN_FILE = os.path.join(BASE_DIR, "cooldowns.json")
COOLDOWN_LIMIT = 5  # Max tickets
RESET_MINUTES = 20  # Reset time if not exhausted
COOLDOWN_HOURS = 2  # Cooldown time if exhausted

if not os.path.exists(COOLDOWN_FILE):
    with open(COOLDOWN_FILE, "w") as f:
        json.dump({}, f, indent=4)
    staff_cooldowns = {}
else:
    with open(COOLDOWN_FILE, "r") as f:
        try:
            staff_cooldowns = json.load(f)
        except json.JSONDecodeError:
            staff_cooldowns = {}

def save_cooldowns():
    with open(COOLDOWN_FILE, "w") as f:
        json.dump(staff_cooldowns, f, indent=4)
    # Auto-backup to GitHub
    if BACKUP_ENABLED:
        backup_to_github(["cooldowns.json"], async_mode=True)

def add_claim_to_cooldown(staff_id):
    """Add a claim to staff's cooldown tracker"""
    staff_key = str(staff_id)
    now = datetime.datetime.now()
    
    if staff_key not in staff_cooldowns:
        staff_cooldowns[staff_key] = {
            "cycle_start": now.isoformat(),
            "claims_in_cycle": 0,
            "exhausted_cooldown_until": None
        }
    
    # Check if we're in exhausted cooldown
    exhausted_until_str = staff_cooldowns[staff_key].get("exhausted_cooldown_until")
    if exhausted_until_str:
        exhausted_until = datetime.datetime.fromisoformat(exhausted_until_str)
        if now >= exhausted_until:
            # Exhausted cooldown expired, start fresh cycle
            staff_cooldowns[staff_key] = {
                "cycle_start": now.isoformat(),
                "claims_in_cycle": 1,
                "exhausted_cooldown_until": None
            }
            save_cooldowns()
            return
    
    # Check if normal cycle has expired (20 minutes)
    cycle_start = datetime.datetime.fromisoformat(staff_cooldowns[staff_key]["cycle_start"])
    time_since_start = now - cycle_start
    
    if time_since_start >= datetime.timedelta(minutes=RESET_MINUTES):
        # Cycle expired, reset to fresh
        staff_cooldowns[staff_key] = {
            "cycle_start": now.isoformat(),
            "claims_in_cycle": 1,
            "exhausted_cooldown_until": None
        }
    else:
        # Add to current cycle
        staff_cooldowns[staff_key]["claims_in_cycle"] += 1
        
        # Check if exhausted (hit limit)
        if staff_cooldowns[staff_key]["claims_in_cycle"] >= COOLDOWN_LIMIT:
            # Set exhausted cooldown (2 hours from now)
            exhausted_until = now + datetime.timedelta(hours=COOLDOWN_HOURS)
            staff_cooldowns[staff_key]["exhausted_cooldown_until"] = exhausted_until.isoformat()
    
    save_cooldowns()

def is_staff_on_cooldown(staff_id):
    """Check if staff is on cooldown"""
    staff_key = str(staff_id)
    now = datetime.datetime.now()
    
    if staff_key not in staff_cooldowns:
        return False, None, 0
    
    # Check exhausted cooldown first
    exhausted_until_str = staff_cooldowns[staff_key].get("exhausted_cooldown_until")
    if exhausted_until_str:
        exhausted_until = datetime.datetime.fromisoformat(exhausted_until_str)
        if now < exhausted_until:
            # Still in exhausted cooldown
            time_left = exhausted_until - now
            return True, time_left, COOLDOWN_LIMIT
        else:
            # Exhausted cooldown expired, reset
            staff_cooldowns[staff_key] = {
                "cycle_start": now.isoformat(),
                "claims_in_cycle": 0,
                "exhausted_cooldown_until": None
            }
            save_cooldowns()
            return False, None, 0
    
    # Check normal cycle
    cycle_start = datetime.datetime.fromisoformat(staff_cooldowns[staff_key]["cycle_start"])
    time_since_start = now - cycle_start
    
    if time_since_start >= datetime.timedelta(minutes=RESET_MINUTES):
        # Cycle expired, reset
        staff_cooldowns[staff_key] = {
            "cycle_start": now.isoformat(),
            "claims_in_cycle": 0,
            "exhausted_cooldown_until": None
        }
        save_cooldowns()
        return False, None, 0
    
    current_claims = staff_cooldowns[staff_key]["claims_in_cycle"]
    return False, None, current_claims

def get_claim_count(staff_id):
    """Get current claim count for staff"""
    staff_key = str(staff_id)
    now = datetime.datetime.now()
    
    if staff_key not in staff_cooldowns:
        return 0
    
    # Check if in exhausted cooldown
    exhausted_until_str = staff_cooldowns[staff_key].get("exhausted_cooldown_until")
    if exhausted_until_str:
        exhausted_until = datetime.datetime.fromisoformat(exhausted_until_str)
        if now < exhausted_until:
            return COOLDOWN_LIMIT  # Show as full
    
    # Check if cycle expired
    cycle_start = datetime.datetime.fromisoformat(staff_cooldowns[staff_key]["cycle_start"])
    time_since_start = now - cycle_start
    
    if time_since_start >= datetime.timedelta(minutes=RESET_MINUTES):
        # Cycle expired, reset
        staff_cooldowns[staff_key] = {
            "cycle_start": now.isoformat(),
            "claims_in_cycle": 0,
            "exhausted_cooldown_until": None
        }
        save_cooldowns()
        return 0
    
    return staff_cooldowns[staff_key]["claims_in_cycle"]

# ---------------------------
# LOAD / SAVE SALES
# ---------------------------
if not os.path.exists(SALES_FILE):
    with open(SALES_FILE, "w") as f:
        json.dump({}, f, indent=4)
    sales_data = {}
else:
    with open(SALES_FILE, "r") as f:
        try:
            sales_data = json.load(f)
        except json.JSONDecodeError:
            sales_data = {}

def save_sales():
    with open(SALES_FILE, "w") as f:
        json.dump(sales_data, f, indent=4)
    # Auto-backup to GitHub
    if BACKUP_ENABLED:
        backup_to_github(["sales.json"], async_mode=True)

def add_sale(staff_id, amount, description="Premium Sale"):
    staff_key = str(staff_id)
    if staff_key not in sales_data:
        sales_data[staff_key] = {"total": 0, "sales": []}
    
    sale_entry = {
        "amount": amount,
        "description": description,
        "timestamp": datetime.datetime.now().isoformat()
    }
    sales_data[staff_key]["sales"].append(sale_entry)
    sales_data[staff_key]["total"] += amount
    save_sales()

def get_sales(staff_id):
    staff_key = str(staff_id)
    return sales_data.get(staff_key, {"total": 0, "sales": []})

def reset_sales(staff_id):
    """Reset sales data for a staff member after salary payment"""
    staff_key = str(staff_id)
    if staff_key in sales_data:
        sales_data[staff_key] = {"total": 0, "sales": []}
        save_sales()
        return True
    return False

def calculate_salary(total_sales):
    """Calculate salary with cap"""
    COMMISSION_RATE = 0.10
    SALARY_CAP = 30000
    calculated = int(total_sales * COMMISSION_RATE)
    return min(calculated, SALARY_CAP)

def is_salary_maxed(staff_id):
    """Check if staff has reached salary cap"""
    SALARY_CAP = 30000
    staff_sales = get_sales(staff_id)
    salary = calculate_salary(staff_sales["total"])
    return salary >= SALARY_CAP

# Salary cap constant
SALARY_CAP = 30000
COMMISSION_RATE = 0.10

# Admin role for salary payment
ADMIN_ROLE_ID = 1458390940959117356

def add_ticket(user_id, channel_id):
    active_tickets[user_id] = channel_id
    save_tickets()

def remove_ticket(user_id):
    if user_id in active_tickets:
        del active_tickets[user_id]
        save_tickets()

def increment_ticket_counter():
    global ticket_count
    ticket_count += 1
    save_tickets()
    return ticket_count


# ---------------------------
# EMBEDS
# ---------------------------
async def send_ticket_panel(bot: commands.Bot, panel_type="all"):
    panels = []
    if panel_type in ["all", "biasa"]:
        panels.append({
            "channel_id": TICKET_PANEL_CHANNEL_ID,
            "message_id": 1458004446473883732,
            "embed": dc.Embed(title="🎫 Ticket Vora Hub", description=TICKET_BIASA_DESC, color=VORA_BLUE),
            "view": TicketPanelButtons()
        })
    if panel_type in ["all", "x8"]:
        panels.append({
            "channel_id": TICKET_PANEL_CHANNEL_ID_X8,
            "message_id": 1443996005862478018,
            "embed": dc.Embed(title="🎫 Ticket X8", description=TICKET_X8_DESC, color=VORA_BLUE),
            "view": TicketX8Button()
        })

    for panel in panels:
        channel = bot.get_channel(panel["channel_id"])
        if not channel:
            print(f"[PANEL] Channel {panel['channel_id']} tidak ditemukan.")
            continue
        try:
            msg = await channel.fetch_message(panel["message_id"])
            await msg.edit(embed=panel["embed"], view=panel["view"])
            print(f"[PANEL] Message {panel['message_id']} berhasil di-edit.")
        except dc.NotFound:
            await channel.send(embed=panel["embed"], view=panel["view"])
            print(f"[PANEL] Message {panel['message_id']} tidak ditemukan, baru dibuat.")
        except Exception as e:
            print(f"[PANEL] Gagal edit/send message {panel['message_id']}: {e}")

TICKET_BIASA_DESC = """\
**Ticket Explanation**
These tickets are intended to open new channels. This is specifically for ticket makers and staff.
The ticket creator can press any button according to the category.

**Button Style**
🏛️ : Press this button if you want to buy premium.
🎥 : Press this button if you want to get the Content Creator role (min 1k YouTube subs & 1k TikTok followers).
📬 : Press this button if you want to report a bug in the game or behavior of other members that violates the rules.

**Ticket Requirements**
• Don't press tickets carelessly.
• Press only when necessary.
• Opening a ticket without a clear reason is prohibited.
• Closing a ticket without explanation is not allowed.
"""

TICKET_X8_DESC = """\
🎣 Event server VoraHub.
Yuk ikut event server boost X8 biar peluang dapet ikan rare makin besar 💎

**📍 Tentang sistem Event**:
- Host akan menjalankan **private server Fish It dengan Server Luck x8**
- Total slot tersedia: **19 pemain maksimal** + 1 Host & BMKG
- Sistem **first come, first serve** — siapa cepat dia dapat 🎯

✨ Cara bergabung:
1. Klik tombol "🚀 Register Event" di bawah.
2. Isi data sesuai format tiket (username & jumlah slot yang diinginkan).
3. Setelah konfirmasi pembayaran, kamu akan ditambahkan ke server boost aktif.

⚡ Ayo isi slotmu sebelum penuh
"""

TICKET_MIDMAN_DESC = """\
𝗙𝗘𝗘 𝗠𝗜𝗗𝗠𝗔𝗡 / 𝗠𝗖

———————————

𝟷ᴋ — 𝟸𝟶ᴋ = ғᴇᴇ 𝟷ᴋ
𝟸𝟷ᴋ — 𝟻𝟶ᴋ = ғᴇᴇ 𝟸ᴋ
𝟻𝟷ᴋ — 𝟾𝟶ᴋ = ғᴇᴇ 𝟹ᴋ
𝟾𝟷ᴋ — 𝟷𝟹𝟶ᴋ = ғᴇᴇ 𝟺ᴋ
𝟷𝟹𝟷ᴋ — 𝟸𝟶𝟶ᴋ = ғᴇᴇ 𝟻ᴋ
𝟸𝟶𝟷ᴋ — 𝟸𝟾𝟶ᴋ = ғᴇᴇ 𝟼ᴋ
𝟸𝟾𝟷ᴋ — 𝟹𝟻𝟶ᴋ = ғᴇᴇ 𝟽ᴋ
𝟹𝟻𝟷ᴋ — ᴅsᴛ = ғᴇᴇ 𝟷𝟶ᴋ

𝗝𝗜𝗞𝗔 𝗧𝗥𝗫 𝗧𝗜𝗗𝗔𝗞 𝗝𝗔𝗗𝗜 𝗧𝗔𝗣𝗜 𝗦𝗨𝗗𝗔𝗛 𝗧𝗥𝗔𝗡𝗦𝗙𝗘𝗥, 𝗙𝗘𝗘 𝗧𝗘𝗧𝗔𝗣 𝗞𝗘 𝗣𝗢𝗧𝗢𝗡𝗚.

———————————

𝗟𝗘𝗕𝗜𝗛 𝗕𝗔𝗜𝗞 𝗞𝗘𝗟𝗨𝗔𝗥 𝗗𝗨𝗜𝗧 𝗕𝗨𝗔𝗧 𝗙𝗘𝗘 𝗔𝗗𝗠𝗜𝗡 𝗗𝗔𝗥𝗜 𝗣𝗔𝗗𝗔 𝗞𝗘𝗡𝗔 𝗦𝗖𝗔𝗠/𝗝𝗔𝗗𝗜 𝗞𝗢𝗥𝗕𝗔𝗡 𝗣𝗘𝗡𝗜𝗣𝗨𝗔𝗡 !!

Klik tombol Di bawah Ini Untuk membuat Ticket Midman.
"""

# ---------------------------
# VIEWS
# ---------------------------
class TicketPanelButtons(ui.View):
    def __init__(self):
        super().__init__(timeout=None)

    @ui.button(emoji="🏛️", label="Purchase", style=dc.ButtonStyle.green, custom_id="ticket_premium")
    async def premium(self, interaction: Interaction, button: ui.Button):
        await create_ticket(interaction, "Premium Purchase")

    @ui.button(emoji="🎥", label="Content Creator", style=dc.ButtonStyle.red, custom_id="ticket_creator")
    async def creator(self, interaction: Interaction, button: ui.Button):
        await create_ticket(interaction, "Content Creator Request")

    @ui.button(emoji="📬", label="Report", style=dc.ButtonStyle.blurple, custom_id="ticket_report")
    async def report(self, interaction: Interaction, button: ui.Button):
        await create_ticket(interaction, "Bug / Misconduct Report")

class TicketX8Button(ui.View):
    def __init__(self):
        super().__init__(timeout=None)

    @ui.button(label="🚀 Register Event", style=dc.ButtonStyle.green, custom_id="ticket_x8")
    async def create_ticket_button(self, interaction: Interaction, button: ui.Button):
        await create_ticket(interaction, "X8 Ticket")

# ---------------------------
# MIDMAN MODAL & VIEW
# ---------------------------
class MidmanModal(ui.Modal, title="🤝 Form Midman Ticket"):
    item = ui.TextInput(
        label="Item / Akun",
        placeholder="Contoh: Akun Roblox / Ikan Betta",
        required=True,
        max_length=100
    )
    buyer = ui.TextInput(
        label="Buyer (Username / ID)",
        placeholder="Username atau ID Discord buyer",
        required=True,
        max_length=100
    )
    seller = ui.TextInput(
        label="Seller (Username / ID)", 
        placeholder="Username atau ID Discord seller",
        required=True,
        max_length=100
    )
    harga = ui.TextInput(
        label="Harga (Angka saja, No barter ya koncol)",
        placeholder="Contoh: 50000",
        required=True,
        max_length=20
    )
    payment = ui.TextInput(
        label="Payment (Pisahkan dengan /)",
        placeholder="Contoh: Dana / Gopay / QRIS",
        required=True,
        max_length=100
    )

    async def on_submit(self, interaction: Interaction):
        await create_midman_ticket(
            interaction,
            item=self.item.value,
            buyer=self.buyer.value,
            seller=self.seller.value,
            harga=self.harga.value,
            payment=self.payment.value
        )

class TicketMidmanButton(ui.View):
    def __init__(self):
        super().__init__(timeout=None)

    @ui.button(label="🤝 Buat Ticket Midman", style=dc.ButtonStyle.green, custom_id="ticket_midman")
    async def create_midman_ticket_button(self, interaction: Interaction, button: ui.Button):
        # Show the modal form
        await interaction.response.send_modal(MidmanModal())

# ---------------------------
# DONE BUTTON VIEW (appears after whitelist)
# ---------------------------
class DoneButtonView(ui.View):
    def __init__(self, is_premium=False):
        super().__init__(timeout=None)
        self.is_premium = is_premium

    @ui.button(label="Done", style=dc.ButtonStyle.success, emoji="✅", custom_id="done_ticket_confirm")
    async def done_button(self, interaction: Interaction, button: ui.Button):
        user = interaction.user
        guild = interaction.guild
        channel = interaction.channel

        # Check if ticket is already marked as done
        if is_ticket_done(channel.id):
            await interaction.response.send_message(
                "❌ Ticket ini sudah di-mark sebagai **Done** sebelumnya!\n"
                "Sales sudah tercatat untuk staff yang handle ticket ini.",
                ephemeral=True
            )
            return

        # Find ticket creator
        ticket_creator_id = None
        for uid, cid in active_tickets.items():
            if cid == channel.id:
                ticket_creator_id = uid
                break

        # Check if user is the ticket creator
        if user.id != ticket_creator_id:
            await interaction.response.send_message("❌ Hanya pembuat ticket yang bisa menekan tombol Done.", ephemeral=True)
            return

        # Check if ticket is claimed
        claimer_id = get_claim(channel.id)
        if not claimer_id:
            await interaction.response.send_message("❌ Ticket ini belum di-claim oleh staff. Tidak ada yang bisa dikreditkan.", ephemeral=True)
            return

        # Get claimer member
        claimer = guild.get_member(claimer_id)
        if not claimer:
            await interaction.response.send_message("❌ Staff yang claim ticket tidak ditemukan.", ephemeral=True)
            return

        # Determine sale amount based on ticket type
        sale_amount = 20000 if self.is_premium else 0  # Default premium price

        if sale_amount == 0:
            await interaction.response.send_message("❌ Ticket ini bukan ticket premium, tidak ada sales yang dicatat.", ephemeral=True)
            return

        # Add sale to the claimer
        add_sale(claimer_id, sale_amount, f"Premium Sale - Ticket {channel.name}")

        # Get updated stats
        staff_sales = get_sales(claimer_id)
        total = staff_sales["total"]

        # Send confirmation
        embed = dc.Embed(
            title="✅ Ticket Selesai & Sales Tercatat",
            description=f"Terima kasih {user.mention}! Ticket telah ditandai selesai.",
            color=VORA_BLUE
        )
        embed.add_field(name="Staff yang Handle", value=claimer.mention, inline=True)
        embed.add_field(name="Credit Sales", value=f"IDR {sale_amount:,}", inline=True)
        embed.add_field(name="Total Sales Staff", value=f"IDR {total:,}", inline=True)
        embed.set_footer(text="VoraHub Sales Tracker")

        await interaction.response.send_message(embed=embed)

        # Notify the claimer
        try:
            await claimer.send(
                f"🎉 Selamat! Kamu mendapat credit sales **IDR {sale_amount:,}** dari ticket **{channel.name}**!\n"
                f"Total sales kamu sekarang: **IDR {total:,}**"
            )
        except:
            # If DM fails, send in channel
            await channel.send(f"🎉 {claimer.mention} mendapat credit sales **IDR {sale_amount:,}**!")

        # Mark ticket as done to prevent double-done
        mark_ticket_done(channel.id)

class TicketControlView(ui.View):
    def __init__(self, is_premium=False, is_x8=False):
        super().__init__(timeout=None)
        self.is_premium = is_premium
        self.is_x8 = is_x8
        # Claim ticket button - only for premium tickets
        if self.is_premium:
            self.add_item(ui.Button(label="Claim Ticket", style=dc.ButtonStyle.green, emoji="✋", custom_id="claim_ticket"))
        # Close ticket button
        self.add_item(ui.Button(label="Close Ticket", style=dc.ButtonStyle.red, emoji="🔒", custom_id="close_ticket"))
        # Payment button if premium
        if self.is_premium:
            self.add_item(ui.Button(label="💳 Bayar Sekarang", style=dc.ButtonStyle.blurple, custom_id="pay_now"))
        # Payment button for X8 tickets
        if self.is_x8:
            self.add_item(ui.Button(label="💳 Bayar Sekarang", style=dc.ButtonStyle.blurple, custom_id="pay_now_x8"))

    async def interaction_check(self, interaction: Interaction) -> bool:
        cid = interaction.data.get("custom_id")
        if cid == "claim_ticket":
            return await self.claim_ticket_callback(interaction)
        elif cid == "close_ticket":
            return await self.close_ticket_callback(interaction)
        elif cid == "pay_now":
            return await self.pay_now_callback(interaction)
        elif cid == "pay_now_x8":
            return await self.pay_now_x8_callback(interaction)
        return True

    async def claim_ticket_callback(self, interaction: Interaction):
        user = interaction.user
        guild = interaction.guild
        channel = interaction.channel
        staff_role = guild.get_role(STAFF_ROLE_ID)
        helper_role = guild.get_role(HELPER_ROLE_ID)

        # Check if user is staff
        if staff_role not in user.roles and helper_role not in user.roles:
            await interaction.response.send_message("❌ Hanya staff yang bisa claim ticket.", ephemeral=True)
            return False

        # Check if user is admin (bypass all limits)
        admin_role = guild.get_role(ADMIN_ROLE_ID)
        is_admin = admin_role in user.roles

        # Check if staff has reached salary cap (skip for admin)
        if not is_admin and is_salary_maxed(user.id):
            staff_sales = get_sales(user.id)
            current_salary = calculate_salary(staff_sales["total"])
            await interaction.response.send_message(
                f"❌ **Gaji kamu sudah mencapai batas maksimal IDR {current_salary:,}!**\n\n"
                f"Kamu tidak bisa claim ticket baru sampai gaji dibayar oleh admin.\n"
                f"Hubungi admin untuk pembayaran gaji dengan command `/gajisudahbayar`.",
                ephemeral=True
            )
            return False

        # Check if staff is on cooldown (skip for admin)
        if not is_admin:
            on_cooldown, time_left, current_count = is_staff_on_cooldown(user.id)
            if on_cooldown:
                hours = int(time_left.total_seconds() // 3600)
                minutes = int((time_left.total_seconds() % 3600) // 60)
                await interaction.response.send_message(
                    f"⏰ **Quota habis! Cooldown aktif**\n\n"
                    f"Kamu sudah claim {COOLDOWN_LIMIT} ticket dan quota habis.\n"
                    f"Cooldown berakhir dalam: **{hours} jam {minutes} menit**\n\n"
                    f"💡 **Tip:** Kalau quota belum habis, reset otomatis setiap {RESET_MINUTES} menit!",
                    ephemeral=True
                )
                return False

        # Check if already claimed
        existing_claim = get_claim(channel.id)
        if existing_claim:
            if existing_claim == user.id:
                await interaction.response.send_message("✅ Kamu sudah claim ticket ini.", ephemeral=True)
                return False
            else:
                claimer = guild.get_member(existing_claim)
                claimer_name = claimer.mention if claimer else "Unknown"
                await interaction.response.send_message(f"❌ Ticket ini sudah di-claim oleh {claimer_name}.", ephemeral=True)
                return False

        # Add claim
        add_claim(channel.id, user.id)
        
        # Add to cooldown tracker (skip for admin)
        if not is_admin:
            add_claim_to_cooldown(user.id)
        
        # Get current claim count
        claim_count = get_claim_count(user.id) if not is_admin else 0
        remaining = COOLDOWN_LIMIT - claim_count if not is_admin else 999  # Show unlimited for admin

        # Find ticket creator
        ticket_creator_id = None
        ticket_source = x8_tickets if self.is_x8 else active_tickets
        for uid, cid in ticket_source.items():
            if cid == channel.id:
                ticket_creator_id = uid
                break

        # Update permissions - hide from all staff except claimer and creator
        ticket_creator = guild.get_member(ticket_creator_id) if ticket_creator_id else None
        
        # Hide from staff roles
        await channel.set_permissions(staff_role, view_channel=False)
        await channel.set_permissions(helper_role, view_channel=False)
        
        # Allow claimer
        await channel.set_permissions(user, view_channel=True, send_messages=True)
        
        # Allow creator
        if ticket_creator:
            await channel.set_permissions(ticket_creator, view_channel=True, send_messages=True)

        # Success message with quota info
        quota_msg = ""
        if is_admin:
            quota_msg = "\n\n👑 **Admin Mode:** Unlimited quota - No cooldown!"
        elif remaining > 0:
            quota_msg = f"\n\n📊 Sisa quota: **{remaining}/{COOLDOWN_LIMIT}** ticket\n💡 Reset otomatis dalam {RESET_MINUTES} menit jadi 5/5 lagi!"
        else:
            quota_msg = f"\n\n⚠️ Quota habis! Cooldown {COOLDOWN_HOURS} jam dimulai sekarang."
        
        await interaction.response.send_message(
            f"✅ {user.mention} telah **claim** ticket ini! Ticket sekarang hanya terlihat oleh kamu dan pembuat ticket.{quota_msg}",
            ephemeral=False
        )
        return True


    async def close_ticket_callback(self, interaction: Interaction):
        user = interaction.user
        guild = interaction.guild
        staff_role = guild.get_role(STAFF_ROLE_ID)
        helper_role = guild.get_role(HELPER_ROLE_ID)

        if staff_role not in user.roles and helper_role not in user.roles:
            await interaction.response.send_message("❌ Hanya staff yang bisa menutup ticket.", ephemeral=True)
            return False

        channel = interaction.channel
        await interaction.response.send_message("📁 Membuat transcript…", ephemeral=True)
        messages = []
        async for msg in channel.history(limit=None, oldest_first=True):
            ts = msg.created_at.strftime("%Y-%m-%d %H:%M:%S")
            content = msg.content or "*[Tidak ada teks]*"
            if msg.attachments:
                content += "\n" + "\n".join([f"[Attachment] {a.url}" for a in msg.attachments])
            messages.append(f"**{msg.author}** [{ts}]:\n{content}\n")

        transcript = "\n".join(messages)
        log = guild.get_channel(TICKET_LOG_CHANNEL_ID)
        for i in range(0, len(transcript), 4096):
            part = transcript[i:i+4096]
            embed = dc.Embed(title=f"📝 Transcript — {channel.name}", description=part, color=VORA_BLUE)
            await log.send(embed=embed)
        await log.send(f"✅ Transcript ticket **{channel.name}** selesai.")

        # Remove from active tickets/x8 tickets and claims
        if self.is_x8:
             for uid, cid in list(x8_tickets.items()):
                if cid == channel.id:
                    del x8_tickets[uid]
             save_x8_tickets()
        else:
             for uid, cid in list(active_tickets.items()):
                if cid == channel.id:
                    del active_tickets[uid]
             save_tickets()
        remove_claim(channel.id)
        remove_done_ticket(channel.id)  # Clean up done tickets list
        await channel.delete()
        return True

    async def pay_now_callback(self, interaction: Interaction):
        if not self.is_premium:
            await interaction.response.send_message("❌ Tidak ada pembayaran di ticket ini.", ephemeral=True)
            return False
        await send_payment_embed(interaction.channel)
        await interaction.response.send_message("📄 Informasi pembayaran dikirim!", ephemeral=True)
        return True
    
    async def pay_now_x8_callback(self, interaction: Interaction):
        if not self.is_x8:
            await interaction.response.send_message("❌ Tidak ada pembayaran di ticket ini.", ephemeral=True)
            return False
        await interaction.response.send_message(
            "🧾 **QRIS Payment X8 Event:**\nhttps://cdn.discordapp.com/attachments/1448212332244242524/1461696579055521944/IMG_2466.png",
            ephemeral=True
        )
        return True

# ---------------------------
# MIDMAN TICKET CONTROL VIEW (khusus Midman)
# ---------------------------
class MidmanTicketControlView(ui.View):
    def __init__(self):
        super().__init__(timeout=None)
        # Claim ticket button for Midman
        self.add_item(ui.Button(label="Claim Ticket", style=dc.ButtonStyle.green, emoji="✋", custom_id="claim_midman_ticket"))
        # Close ticket button
        self.add_item(ui.Button(label="Close Ticket", style=dc.ButtonStyle.red, emoji="🔒", custom_id="close_midman_ticket"))
        # Done button for Midman
        self.add_item(ui.Button(label="Done ✅", style=dc.ButtonStyle.blurple, emoji="✅", custom_id="done_midman_ticket"))

    async def interaction_check(self, interaction: Interaction) -> bool:
        cid = interaction.data.get("custom_id")
        if cid == "claim_midman_ticket":
            return await self.claim_midman_callback(interaction)
        elif cid == "close_midman_ticket":
            return await self.close_midman_callback(interaction)
        elif cid == "done_midman_ticket":
            return await self.done_midman_callback(interaction)
        return True

    async def claim_midman_callback(self, interaction: Interaction):
        user = interaction.user
        guild = interaction.guild
        channel = interaction.channel
        midman_role = guild.get_role(MIDMAN_ROLE_ID)

        # Check if user has Midman role
        if midman_role not in user.roles:
            await interaction.response.send_message("❌ Hanya Midman yang bisa claim ticket ini.", ephemeral=True)
            return False

        # Check if already claimed
        existing_claim = get_claim(channel.id)
        if existing_claim:
            if existing_claim == user.id:
                await interaction.response.send_message("✅ Kamu sudah claim ticket ini.", ephemeral=True)
                return False
            else:
                claimer = guild.get_member(existing_claim)
                claimer_name = claimer.mention if claimer else "Unknown"
                await interaction.response.send_message(f"❌ Ticket ini sudah di-claim oleh {claimer_name}.", ephemeral=True)
                return False

        # Add claim
        add_claim(channel.id, user.id)

        # Find ticket creator (from midman_tickets)
        ticket_creator_id = None
        for uid, cid in midman_tickets.items():
            if cid == channel.id:
                ticket_creator_id = uid
                break

        # Update permissions - hide from other midman, only claimer and creator can see
        ticket_creator = guild.get_member(ticket_creator_id) if ticket_creator_id else None
        
        # Hide from midman role
        await channel.set_permissions(midman_role, view_channel=False)
        
        # Allow claimer
        await channel.set_permissions(user, view_channel=True, send_messages=True)
        
        # Allow creator
        if ticket_creator:
            await channel.set_permissions(ticket_creator, view_channel=True, send_messages=True)

        await interaction.response.send_message(
            f"✅ {user.mention} telah **claim** ticket Midman ini!\n"
            f"Ticket sekarang hanya terlihat oleh kamu dan pembuat ticket.",
            ephemeral=False
        )
        return True

    async def close_midman_callback(self, interaction: Interaction):
        user = interaction.user
        guild = interaction.guild
        midman_role = guild.get_role(MIDMAN_ROLE_ID)

        # Check if user has Midman role
        if midman_role not in user.roles:
            await interaction.response.send_message("❌ Hanya Midman yang bisa menutup ticket ini.", ephemeral=True)
            return False

        channel = interaction.channel
        await interaction.response.send_message("📁 Membuat transcript…", ephemeral=True)
        messages = []
        async for msg in channel.history(limit=None, oldest_first=True):
            ts = msg.created_at.strftime("%Y-%m-%d %H:%M:%S")
            content = msg.content or "*[Tidak ada teks]*"
            if msg.attachments:
                content += "\n" + "\n".join([f"[Attachment] {a.url}" for a in msg.attachments])
            messages.append(f"**{msg.author}** [{ts}]:\n{content}\n")

        transcript = "\n".join(messages)
        log = guild.get_channel(TICKET_LOG_CHANNEL_ID)
        for i in range(0, len(transcript), 4096):
            part = transcript[i:i+4096]
            embed = dc.Embed(title=f"📝 Transcript Midman — {channel.name}", description=part, color=VORA_BLUE)
            await log.send(embed=embed)
        await log.send(f"✅ Transcript ticket Midman **{channel.name}** selesai.")

        # Remove from midman tickets and claims
        for uid, cid in list(midman_tickets.items()):
            if cid == channel.id:
                del midman_tickets[uid]
        save_midman_tickets()
        remove_claim(channel.id)
        remove_done_ticket(channel.id)
        await channel.delete()
        return True

    async def done_midman_callback(self, interaction: Interaction):
        user = interaction.user
        guild = interaction.guild
        channel = interaction.channel
        midman_role = guild.get_role(MIDMAN_ROLE_ID)

        # Check if user has Midman role (only Midman can mark as done)
        if midman_role not in user.roles:
            await interaction.response.send_message("❌ Hanya Midman yang bisa mark ticket ini sebagai Done.", ephemeral=True)
            return False

        # Check if ticket is already marked as done
        if is_ticket_done(channel.id):
            await interaction.response.send_message(
                "❌ Ticket ini sudah di-mark sebagai **Done** sebelumnya!",
                ephemeral=True
            )
            return False

        # Check if ticket is claimed
        claimer_id = get_claim(channel.id)
        if not claimer_id:
            await interaction.response.send_message("❌ Ticket ini belum di-claim. Claim dulu sebelum mark Done.", ephemeral=True)
            return False

        # Only the claimer can mark as done
        if claimer_id != user.id:
            claimer = guild.get_member(claimer_id)
            claimer_name = claimer.mention if claimer else "Unknown"
            await interaction.response.send_message(f"❌ Hanya {claimer_name} (yang claim) yang bisa mark Done.", ephemeral=True)
            return False

        # Mark as done
        mark_ticket_done(channel.id)

        embed = dc.Embed(
            title="✅ Transaksi Midman Selesai!",
            description=(
                f"Ticket Midman telah ditandai selesai oleh {user.mention}.\n\n"
                "Terima kasih telah menggunakan jasa Midman VoraHub! 🤝"
            ),
            color=0x00ff00
        )
        embed.set_footer(text="VoraHub Midman System • Safe Transaction")

        await interaction.response.send_message(embed=embed)
        return True

class PaymentActionView(ui.View):
    def __init__(self):
        super().__init__(timeout=None)

    @ui.button(label="📤 Send Proof", style=dc.ButtonStyle.green, custom_id="payment_send_proof")
    async def send_proof(self, interaction: Interaction, button: ui.Button):
        await interaction.response.send_message("Silakan **upload bukti transfer** di chat ticket ini.", ephemeral=True)

    @ui.button(label="💳 Open QRIS", style=dc.ButtonStyle.blurple, custom_id="payment_open_qris")
    async def open_qris(self, interaction: Interaction, button: ui.Button):
        await interaction.response.send_message(
            "🧾 **QRIS Payment:**\nhttps://cdn.discordapp.com/attachments/1436968124699119636/1443793945581846619/VoraQris.png",
            ephemeral=True
        )

async def send_payment_embed(channel):
    embed = dc.Embed(
        title="🛒 Premium Purchase Information",
        description=(
            "**💳 Pricelist**\n• Lifetime Premium → IDR 20.000\n\n"
            "**📘 English**\nPay via QRIS then send proof here.\n\n"
            "**📗 Indonesian**\nBayar via QRIS, lalu kirim bukti transfer di sini.\n\n"
            "📨 Kirim bukti transfer di ticket ini.\n👥 Tunggu staff jika butuh bantuan."
        ),
        color=VORA_BLUE
    )
    embed.set_footer(text="Vora Hub Premium • Secure Payment")
    await channel.send(embed=embed, view=PaymentActionView())

# ---------------------------
# CREATE TICKET FUNCTION
# ---------------------------
async def create_ticket(interaction: Interaction, category_name: str):
    user = interaction.user
    guild = interaction.guild
    
    is_x8 = "x8" in category_name.lower()

    # Cek ticket aktif (berbeda storage untuk X8)
    if is_x8:
        if user.id in x8_tickets:
            ch = guild.get_channel(x8_tickets[user.id])
            if ch:
                return await interaction.response.send_message(
                    f"⚠ Kamu masih punya ticket X8 aktif di {ch.mention}.", ephemeral=True
                )
            else:
                # Ghost ticket cleanup
                print(f"[CLEANUP] Removing ghost X8 ticket for user {user.id}")
                remove_x8_ticket(user.id)
                remove_claim(x8_tickets.get(user.id))
                remove_done_ticket(x8_tickets.get(user.id))
        current_ticket_num = increment_x8_ticket_counter()
    else:
        if user.id in active_tickets:
            ch = guild.get_channel(active_tickets[user.id])
            if ch:
                return await interaction.response.send_message(
                    f"⚠ Kamu masih punya ticket aktif di {ch.mention}.", ephemeral=True
                )
            else:
                # Ghost ticket cleanup
                print(f"[CLEANUP] Removing ghost ticket for user {user.id}")
                remove_ticket(user.id)
                remove_claim(active_tickets.get(user.id))
                remove_done_ticket(active_tickets.get(user.id))
        current_ticket_num = increment_ticket_counter()

    # Determine category (with overflow support for regular tickets)
    if is_x8:
        category_id = TICKET_CATEGORY_ID_X8
        category = guild.get_channel(category_id)
    else:
        # Check if primary category is full (Discord limit: 50 channels per category)
        primary_category = guild.get_channel(TICKET_CATEGORY_ID)
        if primary_category and len(primary_category.channels) >= 50:
            # Primary category is full, use secondary category
            category_id = TICKET2_CATEGORY_ID
            category = guild.get_channel(category_id)
            print(f"[TICKET] Primary category full ({len(primary_category.channels)} channels), using secondary category")
        else:
            # Use primary category
            category_id = TICKET_CATEGORY_ID
            category = primary_category
    
    staff_role = guild.get_role(STAFF_ROLE_ID)
    helper_role = guild.get_role(HELPER_ROLE_ID)
    admin_role = guild.get_role(ADMIN_ROLE_ID)
    channel_name = f"{'x8-' if is_x8 else ''}ticket-{current_ticket_num:04}"

    # Build overwrites dictionary
    overwrites = {
        guild.default_role: dc.PermissionOverwrite(view_channel=False),
        user: dc.PermissionOverwrite(view_channel=True, send_messages=True),
        staff_role: dc.PermissionOverwrite(view_channel=True, send_messages=True),
        helper_role: dc.PermissionOverwrite(view_channel=True, send_messages=True)
    }
    
    # Add admin role if it exists
    if admin_role:
        overwrites[admin_role] = dc.PermissionOverwrite(
            view_channel=True, 
            send_messages=True, 
            manage_channels=True,
            manage_messages=True
        )

    ticket_channel = await guild.create_text_channel(
        name=channel_name,
        category=category,
        overwrites=overwrites
    )
    
    # Save to appropriate storage
    if is_x8:
        add_x8_ticket(user.id, ticket_channel.id)
    else:
        add_ticket(user.id, ticket_channel.id)

    is_premium = "premium" in category_name.lower()

    embed = dc.Embed(
        title=f"🎫 Ticket Dibuat — {category_name}",
        description=(
            f"Halo {user.mention}!\n\n"
            f"Ticket kamu telah berhasil dibuat untuk kategori **{category_name}**.\n"
            "Staff akan segera merespons.\n\n"
            "**Jangan close ticket sebelum masalah selesai.**"
        ),
        color=VORA_BLUE
    )
    embed.add_field(name="Pembuat Ticket", value=user.mention, inline=False)
    embed.add_field(name="Kategori", value=category_name, inline=False)
    embed.set_footer(text="Vora Hub Ticket System")

    mentions = []
    if staff_role:
        mentions.append(staff_role.mention)
    if helper_role:
        mentions.append(helper_role.mention)

    # Detect if this is an X8 ticket
    is_x8 = "x8" in category_name.lower()

    await ticket_channel.send(
        content=" ".join(mentions),
        embed=embed,
        view=TicketControlView(is_premium=is_premium, is_x8=is_x8)
    )

    await interaction.response.send_message(f"🎫 Ticket kamu sudah dibuat: {ticket_channel.mention}", ephemeral=True)

    log = guild.get_channel(TICKET_LOG_CHANNEL_ID)
    log_embed = dc.Embed(
        title="📩 Ticket Dibuat",
        description=f"**User:** {user.mention}\n**Kategori:** {category_name}\n\n📌 **Channel:** {ticket_channel.mention}",
        color=VORA_BLUE
    )
    log_embed.set_footer(text="Vora Hub Ticket System • Ticket Log")
    await log.send(embed=log_embed)

# ---------------------------
# CREATE MIDMAN TICKET FUNCTION
# ---------------------------
async def create_midman_ticket(interaction: Interaction, item: str, buyer: str, seller: str, harga: str, payment: str):
    user = interaction.user
    guild = interaction.guild

    # Cek ticket aktif (cek di midman_tickets)
    if user.id in midman_tickets:
        ch = guild.get_channel(midman_tickets[user.id])
        if ch:
            return await interaction.response.send_message(
                f"⚠ Kamu masih punya ticket Midman aktif di {ch.mention}.", ephemeral=True
            )
        else:
            # Ghost ticket cleanup
            print(f"[CLEANUP] Removing ghost Midman ticket for user {user.id}")
            remove_midman_ticket(user.id)
            remove_claim(midman_tickets.get(user.id))
            remove_done_ticket(midman_tickets.get(user.id))

    current_ticket_num = increment_midman_ticket_counter()
    category = guild.get_channel(TICKET_CATEGORY_ID_MIDMAN)
    midman_role = guild.get_role(MIDMAN_ROLE_ID)
    channel_name = f"midman-{current_ticket_num:04}"

    # Overwrites - pembuat ticket, midman role
    overwrites = {
        guild.default_role: dc.PermissionOverwrite(view_channel=False),
        user: dc.PermissionOverwrite(view_channel=True, send_messages=True),
        midman_role: dc.PermissionOverwrite(view_channel=True, send_messages=True)
    }

    # Resolve Buyer & Seller input to add to permissions
    def resolve_member(txt):
        txt = str(txt).replace("<@", "").replace(">", "").replace("!", "").strip()
        if txt.isdigit():
            return guild.get_member(int(txt))
        return None

    buyer_member = resolve_member(buyer)
    seller_member = resolve_member(seller)

    if buyer_member:
        overwrites[buyer_member] = dc.PermissionOverwrite(view_channel=True, send_messages=True)
    
    if seller_member:
        overwrites[seller_member] = dc.PermissionOverwrite(view_channel=True, send_messages=True)

    ticket_channel = await guild.create_text_channel(
        name=channel_name,
        category=category,
        overwrites=overwrites
    )
    add_midman_ticket(user.id, ticket_channel.id)

    # Format harga dengan comma
    try:
        harga_int = int(harga.replace(".", "").replace(",", "").replace(" ", ""))
        harga_formatted = f"IDR {harga_int:,}"
    except:
        harga_formatted = f"IDR {harga}"

    embed = dc.Embed(
        title="🤝 Midman Ticket Dibuat",
        description=(
            f"Halo {user.mention}!\n\n"
            f"Ticket Midman kamu telah berhasil dibuat.\n"
            "Staff Midman akan segera merespons untuk membantu transaksi.\n\n"
            "**⚠️ PENTING:** Fee Midman akan dipotong sesuai harga transaksi."
        ),
        color=VORA_BLUE
    )
    buyer_display = buyer_member.mention if buyer_member else buyer
    seller_display = seller_member.mention if seller_member else seller

    embed.add_field(name="📦 Item / Akun", value=item, inline=False)
    embed.add_field(name="🛒 Buyer", value=buyer_display, inline=True)
    embed.add_field(name="🏪 Seller", value=seller_display, inline=True)
    embed.add_field(name="💰 Harga", value=harga_formatted, inline=True)
    embed.add_field(name="💳 Payment", value=payment, inline=True)
    embed.add_field(name="📝 Pembuat Ticket", value=user.mention, inline=True)
    embed.set_footer(text="VoraHub Midman System • Safe Transaction")

    mentions = []
    if midman_role:
        mentions.append(midman_role.mention)

    await ticket_channel.send(
        content=" ".join(mentions),
        embed=embed,
        view=MidmanTicketControlView()
    )

    await interaction.response.send_message(f"🎫 Ticket Midman kamu sudah dibuat: {ticket_channel.mention}", ephemeral=True)

    log = guild.get_channel(TICKET_LOG_CHANNEL_ID)
    log_embed = dc.Embed(
        title="📩 Midman Ticket Dibuat",
        description=(
            f"**User:** {user.mention}\n"
            f"**Item:** {item}\n"
            f"**Buyer:** {buyer}\n"
            f"**Seller:** {seller}\n"
            f"**Harga:** {harga_formatted}\n"
            f"**Payment:** {payment}\n\n"
            f"📌 **Channel:** {ticket_channel.mention}"
        ),
        color=VORA_BLUE
    )
    log_embed.set_footer(text="VoraHub Midman System • Ticket Log")
    await log.send(embed=log_embed)

# ---------------------------
# VERIF VIEW
# ---------------------------
class VerifView(ui.View):
    def __init__(self):
        super().__init__(timeout=None)

    @ui.button(label="Verifikasi ✔", style=ButtonStyle.green, custom_id="verif_button")
    async def verif(self, interaction: Interaction, button: ui.Button):
        member = interaction.user
        guild = interaction.guild
        unverified = guild.get_role(UNVERIFIED_ROLE_ID)
        member_role = guild.get_role(MEMBER_ROLE_ID)
        if unverified in member.roles:
            await member.remove_roles(unverified)
        if member_role not in member.roles:
            await member.add_roles(member_role)
        await interaction.response.send_message(f"✅ {member.mention}, kamu sudah **terverifikasi**!\nSelamat datang 🎉", ephemeral=True)

    @ui.button(label="Info", style=ButtonStyle.blurple, custom_id="info_button")
    async def info(self, interaction: Interaction, button: ui.Button):
        embed = dc.Embed(
            title="📘 Info & Peraturan Server",
            description=(
                "**Aturan Singkat:**\n"
                "• Hormati semua member.\n"
                "• Dilarang spam, flood, atau iklan.\n"
                "• Gunakan channel sesuai aturan.\n"
                "• Tidak boleh toxic berlebihan.\n"
                "• Laporkan masalah kepada moderator.\n\n"
                "Terima kasih sudah menjaga kenyamanan server 💙"
            ),
            color=VORA_BLUE
        )
        embed.set_footer(text="VoraHub Official • © 2026")
        await interaction.response.send_message(embed=embed, ephemeral=True)

def get_verif_embed():
    embed = dc.Embed(
        title="Verifikasi Member",
        description=(
            "Halo! Untuk bisa mengakses seluruh fitur server, silakan tekan tombol **Verif** di bawah.\n\n"
            "Dengan menekan tombol ini, kamu akan mendapatkan akses penuh ke seluruh channel server.\n"
            "Pastikan sudah membaca aturan server dan siap untuk bergabung secara aktif!\n\n"
            "**Info Penting:**\n"
            "• Bacalah aturan server dengan seksama.\n"
            "• Gunakan channel dengan bijak.\n"
            "• Hormati semua anggota.\n"
            "• Jika ada masalah, hubungi moderator.\n\n"
            "💙 Selamat datang dan semoga betah! 💙"
        ),
        color=VORA_BLUE
    )
    embed.set_footer(text="VoraHub Official • © 2026")
    return embed

# ---------------------------
# CLIENT
# ---------------------------
class Client(commands.Bot):
    def __init__(self):
        intents = dc.Intents.default()
        intents.members = True
        intents.message_content = True
        super().__init__(command_prefix="!", intents=intents)

        self.ticket_panels = [
        {
            "name": "Ticket Biasa",
            "channel_id": TICKET_PANEL_CHANNEL_ID,
            "message_id": 1458004446473883732,
            "embed": dc.Embed(
                title="🎫 Ticket Vora Hub",
                description=TICKET_BIASA_DESC,
                color=VORA_BLUE
            ),
            "view": TicketPanelButtons,
            "tag": None
        },
        {
            "name": "Ticket X8",
            "channel_id": TICKET_PANEL_CHANNEL_ID_X8,
            "message_id": 1443996005862478018,
            "embed": dc.Embed(
                title="🎫 Ticket X8",
                description=TICKET_X8_DESC,
                color=VORA_BLUE
            ),
            "view": TicketX8Button,
            "tag": f"<@&{MEMBER_ROLE_ID}>"   # ⬅ MENTION MEMBER SETIAP EDIT
        },
        {
            "name": "Ticket Midman",
            "channel_id": TICKET_PANEL_CHANNEL_ID_MIDMAN,
            "message_id": None,  # Will be created on first run
            "embed": dc.Embed(
                title="🤝・Midman Ticket",
                description=TICKET_MIDMAN_DESC,
                color=VORA_BLUE
            ).set_footer(text="VoraHub 2026 | .gg/vorahub"),
            "view": TicketMidmanButton,
            "tag": None
        },
        {
            "name": "Verifikasi",
            "channel_id": 1443599341850857562,
            "message_id": 1443640023516708884,
            "embed": get_verif_embed(),
            "view": VerifView,
            "tag": None
        }
    ]

    async def setup_hook(self):
        """Called when bot is starting up - register persistent views here"""
        # Register all persistent views so buttons work after restart
        # These views have timeout=None which makes them persistent
        
        # Ticket panel buttons
        self.add_view(TicketPanelButtons())
        self.add_view(TicketX8Button())
        self.add_view(TicketMidmanButton())
        
        # Ticket control views - need to add multiple instances for different ticket types
        # Regular tickets (premium and non-premium)
        self.add_view(TicketControlView(is_premium=True, is_x8=False))
        self.add_view(TicketControlView(is_premium=False, is_x8=False))
        
        # X8 tickets
        self.add_view(TicketControlView(is_premium=False, is_x8=True))
        
        # Midman tickets
        self.add_view(MidmanTicketControlView())
        
        # Done button views
        self.add_view(DoneButtonView(is_premium=True))
        self.add_view(DoneButtonView(is_premium=False))
        
        # Payment action view
        self.add_view(PaymentActionView())
        
        print("[VIEWS] ✓ All persistent views registered")

    async def on_ready(self):
        print(f"Logged in as {self.user}")
        try:
            synced = await self.tree.sync()
            print(f"✅ Globally vorahub synced {len(synced)} slash commands.")
        except Exception as e:
            print(f"❌ Failed to sync commands: {e}")

        # buat instance view di sini, saat loop sudah berjalan
        for panel in self.ticket_panels:
            await self.auto_edit_panel(
                panel["channel_id"],
                panel["message_id"],
                panel["embed"],
                panel["view"]()  # <-- bikin instance sekarang
            )
        
        # Jalankan auto check whitelist pertama kali saat load
        await self.check_whitelist_tickets()
        
        # Start auto check loop setiap 5 detik
        if not self.auto_check_whitelist_loop.is_running():
            self.auto_check_whitelist_loop.start()
            print("[AUTO-CHECK] ✓ Whitelist auto-check started (every 5 seconds)")

    @tasks.loop(seconds=5)
    async def auto_check_whitelist_loop(self):
        """Auto check setiap 5 detik untuk ticket yang WL tapi belum Done"""
        await self.check_whitelist_tickets()
    
    @auto_check_whitelist_loop.before_loop
    async def before_auto_check(self):
        await self.wait_until_ready()
    
    async def check_whitelist_tickets(self):
        """
        Cek semua ticket aktif:
        - Jika pembuat ticket sudah punya role WL
        - Dan ticket belum di-mark Done
        - Kirim panel Done ke channel tersebut
        """
        # Get first guild (assuming single server bot)
        if not self.guilds:
            return
        
        guild = self.guilds[0]
        wl_role = guild.get_role(WL_ROLE_ID)
        if not wl_role:
            return
        
        # Iterate through all active tickets
        for user_id, channel_id in list(active_tickets.items()):
            try:
                # Get the ticket channel first
                channel = guild.get_channel(channel_id)
                if not channel:
                    continue
                
                # Check if this is a premium ticket (in either primary or secondary category)
                if channel.category_id not in [TICKET_CATEGORY_ID, TICKET2_CATEGORY_ID]:
                    continue
                
                # Check if ticket is already marked as done
                if is_ticket_done(channel_id):
                    continue
                
                # Check if ticket is claimed
                claimer_id = get_claim(channel_id)
                if not claimer_id:
                    continue
                
                # Get the ticket creator
                member = guild.get_member(user_id)
                if not member:
                    continue
                
                # Check if member has WL role
                if wl_role not in member.roles:
                    continue

                # Check for whitelist confirmation message in channel history
                # This ensures we match the specific transaction, not just the user's role
                has_wl_message = False
                try:
                    async for msg in channel.history(limit=50):
                        content = msg.content or ""
                        # Check embeds too
                        if msg.embeds:
                            for emb in msg.embeds:
                                content += " " + (emb.description or "")
                        
                        if "You have been whitelisted! You can access the script via this message" in content:
                            has_wl_message = True
                            break
                except Exception as hist_error:
                    print(f"[AUTO-CHECK] ✗ Error reading history for {channel.name}: {hist_error}")
                    continue
                
                if not has_wl_message:
                    continue
                
                # Check if Done button already exists in recent messages
                has_done_panel = False
                try:
                    async for msg in channel.history(limit=10):
                        # Check if message has Done button view
                        if msg.author.id == self.user.id:
                            content = msg.content or ""
                            if msg.embeds:
                                for emb in msg.embeds:
                                    if "Whitelist Berhasil" in (emb.title or ""):
                                        has_done_panel = True
                                        break
                            if has_done_panel:
                                break
                except:
                    pass
                
                if has_done_panel:
                    # Panel already exists, just mark as done to prevent future checks
                    mark_ticket_done(channel_id)
                    continue
                
                # Send Done panel to this channel
                embed = dc.Embed(
                    title="✅ Whitelist Berhasil!",
                    description=(
                        f"Halo {member.mention}! Kamu sudah berhasil di-whitelist! 🎉\n\n"
                        "Jika kamu **puas dengan pelayanan** staff, silakan klik tombol **Done** di bawah.\n"
                        "Ini akan memberikan credit sales kepada staff yang membantu kamu."
                    ),
                    color=VORA_BLUE
                )
                embed.set_footer(text="VoraHub Premium • Terima kasih!")
                
                await channel.send(
                    embed=embed,
                    view=DoneButtonView(is_premium=True)
                )
                
                # Mark as done immediately to prevent duplicate sends
                mark_ticket_done(channel_id)
                print(f"[AUTO-CHECK] ✓ Sent Done panel to {channel.name} for {member.name}")
                
            except Exception as e:
                print(f"[AUTO-CHECK] ✗ Error checking ticket {channel_id}: {e}")

    async def auto_edit_panel(self, channel_id, message_id, embed, view, tag=None):
        channel = self.get_channel(channel_id)
        if not channel:
            print(f"[PANEL] Channel {channel_id} tidak ditemukan.")
            return
        content = tag if tag else None
        
        # If message_id is provided, try to edit it directly
        if message_id:
            try:
                msg = await channel.fetch_message(message_id)
                await msg.edit(content=content, embed=embed, view=view)
                print(f"[PANEL] Message {message_id} berhasil di-edit.")
                return
            except dc.NotFound:
                print(f"[PANEL] Message {message_id} tidak ditemukan, mencoba mencari pesan terakhir bot...")
                # Fallthrough to search logic
            except Exception as e:
                print(f"[PANEL] Gagal edit message {message_id}: {e}")
                return

        # Smart detection: Search for existing bot message to update
        try:
            # Check last 10 messages for a message from this bot
            async for history_msg in channel.history(limit=10):
                if history_msg.author == self.user:
                    # Found existing bot message! Update it.
                    await history_msg.edit(content=content, embed=embed, view=view)
                    print(f"[PANEL] Berhasil update panel yang sudah ada di {channel.name} (ID: {history_msg.id})")
                    return
            
            # If no existing message found, send new one
            await channel.send(content=content, embed=embed, view=view)
            print(f"[PANEL] Message baru dibuat di channel {channel_id} (tidak ada panel sebelumnya).")
            
        except Exception as e:
            print(f"[PANEL] Gagal auto-detect/send panel: {e}")

    
    async def on_message(self, message: dc.Message):
        if message.author == self.user:
            return

        ALLOWED_CHANNELS = {
            1434540371186024479,
            1434557030076514344,
            1436968124699119636
        }

        print(f"Message from {message.author} in #{message.channel.name}: {message.content}")

        # Check if message contains whitelist confirmation in a ticket channel
        if "You have been whitelisted! You can access the script via this message" in message.content:
            # Check if this is a ticket channel
            channel_id = message.channel.id
            if channel_id in active_tickets.values():
                # Find if this is a premium ticket
                is_premium_ticket = False
                
                # Check if ticket is claimed (only send Done button if claimed)
                claimer_id = get_claim(channel_id)
                if claimer_id:
                    # Determine if premium by checking channel category or name
                    # Check if ticket is in either primary or secondary category
                    if message.channel.category_id in [TICKET_CATEGORY_ID, TICKET2_CATEGORY_ID]:
                        is_premium_ticket = True
                    
                    if is_premium_ticket:
                        # Send Done button panel
                        embed = dc.Embed(
                            title="✅ Whitelist Berhasil!",
                            description=(
                                "Kamu sudah berhasil di-whitelist! 🎉\n\n"
                                "Jika kamu **puas dengan pelayanan** staff, silakan klik tombol **Done** di bawah.\n"
                                "Ini akan memberikan credit sales kepada staff yang membantu kamu."
                            ),
                            color=VORA_BLUE
                        )
                        embed.set_footer(text="VoraHub Premium • Terima kasih!")
                        
                        await message.channel.send(
                            embed=embed,
                            view=DoneButtonView(is_premium=True)
                        )
                        print(f"[DONE PANEL] Sent Done button to {message.channel.name}")

        # Check if WL role is mentioned in a ticket channel
        if message.role_mentions:
            wl_role = message.guild.get_role(WL_ROLE_ID)
            if wl_role and wl_role in message.role_mentions:
                # Check if this is a ticket channel
                channel_id = message.channel.id
                if channel_id in active_tickets.values():
                    # Grant view permissions to WL role
                    try:
                        await message.channel.set_permissions(
                            wl_role,
                            view_channel=True,
                            send_messages=True
                        )
                        
                        # Send confirmation message
                        embed = dc.Embed(
                            title="🔓 Ticket Dibuka untuk WL",
                            description=f"Ticket ini sekarang terlihat oleh role {wl_role.mention}",
                            color=VORA_BLUE
                        )
                        await message.channel.send(embed=embed)
                        print(f"[WL ACCESS] Granted WL role access to ticket {message.channel.name}")
                    except Exception as e:
                        print(f"[WL ACCESS ERROR] Failed to grant permissions: {e}")


        if message.content.startswith('!hello'):
            return await message.channel.send(f'Hello {message.author}!!!')

        if message.content.lower().startswith(('!nigga', '!nigger')):
            return await message.channel.send('Bahlil hitam anjing cok tai')

        if message.channel.id in ALLOWED_CHANNELS:

            if message.content.lower().startswith('beli'):
                return await message.channel.send(
                    f'Jika ingin membeli silahkan membuka ticket pada channel <#{1434769506798010480}>'
                )

            if message.content.lower().startswith('buy'):
                return await message.channel.send(
                    f'If you want to buy, click the ticket button at <#{1434769506798010480}>'
                )

        await self.process_commands(message)

    async def create_welcome_image(self, member, mode):
        CANVAS_W, CANVAS_H = 735, 386

        def draw_text_with_shadow(draw, pos, text, font, fill, shadow_offset=(3, 3)):
            x, y = pos
            draw.text((x + shadow_offset[0], y + shadow_offset[1]), text,
                      font=font, fill=(0, 0, 0, 150), anchor="ms")
            draw.text((x, y), text, font=font, fill=fill, anchor="ms")

        # Background
        background = Image.open("background.jpg").convert("RGBA")
        background = background.resize((CANVAS_W, CANVAS_H))

        if mode == "welcome":
            title = "WELCOME"
            color = (156, 201, 217)
        else:
            title = "GOODBYE"
            color = (156, 201, 217)

        # Ambil avatar
        async with aiohttp.ClientSession() as session:
            async with session.get(member.display_avatar.url) as resp:
                avatar_bytes = await resp.read()

        avatar = Image.open(io.BytesIO(avatar_bytes)).convert("RGBA")

        # Avatar size scaled for 735×386
        AVATAR_SIZE = 170
        BORDER_SIZE = 5
        FULL_SIZE = AVATAR_SIZE + BORDER_SIZE * 2

        # Circle mask
        avatar = avatar.resize((AVATAR_SIZE, AVATAR_SIZE))
        mask = Image.new("L", (AVATAR_SIZE, AVATAR_SIZE), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, AVATAR_SIZE, AVATAR_SIZE), fill=255)
        avatar.putalpha(mask)

        # Frame around avatar
        frame = Image.new("RGBA", (FULL_SIZE, FULL_SIZE), (0, 0, 0, 0))
        ImageDraw.Draw(frame).ellipse((0, 0, FULL_SIZE, FULL_SIZE), fill=(255, 255, 255))
        frame.paste(avatar, (BORDER_SIZE, BORDER_SIZE), avatar)

        # Center avatar
        avatar_x = CANVAS_W // 2 - FULL_SIZE // 2
        avatar_y = 50
        background.paste(frame, (avatar_x, avatar_y), frame)

        # Draw text
        draw = ImageDraw.Draw(background)

        font_big = ImageFont.truetype("DIN-Next-LT-W04-Heavy.ttf", 60)
        font_small = ImageFont.truetype("DIN-Next-LT-W04-Heavy.ttf", 28)

        text_y = avatar_y + FULL_SIZE + 60
        name_y = text_y + 25

        draw_text_with_shadow(draw, (CANVAS_W // 2, text_y), title, font_big, color)
        draw_text_with_shadow(draw, (CANVAS_W // 2, name_y), member.name.upper(), font_small, "white")

        # Output
        buffer = io.BytesIO()
        background.save(buffer, "PNG")
        buffer.seek(0)
        return buffer


    async def on_member_join(self, member):
        WELCOME_CHANNEL = 1434568585132511505
        DEFAULT_ROLE_ID = 1443627247809335429

        channel = member.guild.get_channel(WELCOME_CHANNEL)
        if not channel:
            return

        image = await self.create_welcome_image(member, "welcome")

        await channel.send(
            content=f"Welcome {member.mention} to **{member.guild.name}**! 🎉",
            file=dc.File(image, "welcome.png")
        )

        try:
            await member.send(f"Welcome to **{member.guild.name}**, {member.name}!")
        except:
            print("DM tidak bisa dikirim.")

        role = member.guild.get_role(DEFAULT_ROLE_ID)
        if role:
            try:
                await member.add_roles(role)
                print(f"[ROLE] {member.name} telah diberi role {role.name}")
            except Exception as e:
                print(f"Gagal memberikan role: {e}")

        print(f"[JOIN] {member.name} di {member.guild.name}")

    async def on_member_remove(self, member):
        WELCOME_CHANNEL = 1434568585132511505
        channel = member.guild.get_channel(WELCOME_CHANNEL)
        if not channel:
            return

        image = await self.create_welcome_image(member, "goodbye")

        await channel.send(
            content=f"{member.mention} has left the server 😭.",
            file=dc.File(image, "goodbye.png")
        )
        print(f"[LEAVE] {member.name} dari {member.guild.name}")

client = Client()

@client.tree.command(name="hello", description="Says hello to the user.")
async def hello(interaction: dc.Interaction):
    await interaction.response.send_message(f'Hello {interaction.user.mention}!!!')

@client.tree.command(name="chat",description="Chat Anything With A Bot.")
async def chat(interaction: dc.Interaction, messages: str):
    await interaction.response.send_message(messages)

@client.tree.command(name="kick", description="Kicks a member from the server.")
async def kick(interaction: dc.Interaction, member: dc.Member, reason: str = "No Reason Provided"):
    if not interaction.user.guild_permissions.kick_members:
        return await interaction.response.send_message(
            "You don't have permission to kick members.",
            ephemeral=True
        )

    IMMUNE_USERS = [
        706872385844019200,
        768832997125259315,
        987654321098765432,
    ]

    if member.id in IMMUNE_USERS:
        return await interaction.response.send_message(
            f"❌ {member.mention} cannot be kicked (protected user).",
            ephemeral=True
        )

    try:
        await member.kick(reason=reason)
        await interaction.response.send_message(
            f"{member.mention} has been kicked.\nReason: {reason}"
        )
    except Exception as e:
        await interaction.response.send_message(
            f"Failed to kick {member.mention}. Error: {e}",
            ephemeral=True
        )

@client.tree.command(name="ban", description="Ban a member from the server.")
@app_commands.describe(member="The member to ban", reason="Reason for the ban")
async def ban(interaction: dc.Interaction, member: dc.Member, reason: str = "No reason provided"):
    if not interaction.user.guild_permissions.ban_members:
        return await interaction.response.send_message("You don't have permission to ban members.", ephemeral=True)
    
    IMMUNE_USERS = [
        706872385844019200,
        768832997125259315,
        987654321098765432,
    ]

    if member.id in IMMUNE_USERS:
        return await interaction.response.send_message(
            f"❌ {member.mention} cannot be Ban (protected user).",
            ephemeral=True
        )
    
    try:
        await member.ban(reason=reason)
        await interaction.response.send_message(f"{member.mention} has been banned.\nReason: {reason}")
    except Exception as e:
        await interaction.response.send_message(f"Failed to ban {member.mention}. Error: {e}", ephemeral=True)

@client.tree.command(name="nigger", description="Just a normal command")
@app_commands.describe(member="The member to nigger")
async def nigger(interaction: dc.Interaction, member: dc.Member):
    await interaction.response.send_message(f"{member.mention}'ve been nigger by {interaction.user.mention}")

@client.tree.command(name="warn", description="Warn a member.")
@app_commands.describe(member="The member to warn", reason="Reason for the warning")
async def warn(interaction: dc.Interaction, member: dc.Member, reason: str = "No reason provided"):
    if not interaction.user.guild_permissions.kick_members:
        await interaction.response.send_message("You don't have permission to warn members.", ephemeral=True)
        return

    guild_id = str(interaction.guild.id)
    member_id = str(member.id)

    if guild_id not in warns:
        warns[guild_id] = {}

    if member_id not in warns[guild_id]:
        warns[guild_id][member_id] = []

    warns[guild_id][member_id].append(reason)
    save_warns()

    total_warns = len(warns[guild_id][member_id])
    await interaction.response.send_message(f"{member.mention} has been warned.\nReason: {reason}\nTotal warns: {total_warns}")

@client.tree.command(name="delwarn", description="Remove a warning from a member.")
@app_commands.describe(member="The member to remove a warning from", index="Optional: index of warn to remove (starts from 1)")
async def unwarn(interaction: dc.Interaction, member: dc.Member, index: int = None):
    if not interaction.user.guild_permissions.kick_members:
        await interaction.response.send_message("You don't have permission to remove warns.", ephemeral=True)
        return

    guild_id = str(interaction.guild.id)
    member_id = str(member.id)

    if guild_id not in warns or member_id not in warns[guild_id] or len(warns[guild_id][member_id]) == 0:
        await interaction.response.send_message(f"{member.mention} has no warns.", ephemeral=True)
        return

    if index is None:
        removed_reason = warns[guild_id][member_id].pop()  # Hapus terakhir
    else:
        if index < 1 or index > len(warns[guild_id][member_id]):
            await interaction.response.send_message(f"Invalid index. Member has {len(warns[guild_id][member_id])} warns.", ephemeral=True)
            return
        removed_reason = warns[guild_id][member_id].pop(index-1)

    total_warns = len(warns[guild_id].get(member_id, []))

    if len(warns[guild_id].get(member_id, [])) == 0:
        warns[guild_id].pop(member_id, None)
    if len(warns.get(guild_id, {})) == 0:
        warns.pop(guild_id, None)

    save_warns()
    await interaction.response.send_message(
        f"Removed warn from {member.mention}.\nRemoved reason: {removed_reason}\nTotal warns left: {total_warns}"
    )

@client.tree.command(name="warnlist", description="View all warns of a member.")
@app_commands.describe(member="The member to view warns for")
async def view_warns(interaction: dc.Interaction, member: dc.Member):
    guild_id = str(interaction.guild.id)
    member_id = str(member.id)
    if guild_id not in warns or member_id not in warns[guild_id] or len(warns[guild_id][member_id]) == 0:
        await interaction.response.send_message(f"{member.mention} has no warns.", ephemeral=True)
        return
    member_warns = warns[guild_id][member_id]
    warn_list = "\n".join([f"{i+1}. {reason}" for i, reason in enumerate(member_warns)])
    await interaction.response.send_message(f"Warns for {member.mention}:\n{warn_list}")

@client.tree.command(name="timeout", description="Temporarily mute a member.")
@app_commands.describe(member="The member to timeout", minutes="Duration in minutes", reason="Reason for timeout")
async def timeout(interaction: dc.Interaction, member: dc.Member, minutes: int = 5, reason: str = "No reason provided"):
    if not interaction.user.guild_permissions.moderate_members:
        await interaction.response.send_message("You don't have permission to timeout members.", ephemeral=True)
        return
    
    try:
        await member.timeout(duration=timedelta(minutes=minutes), reason=reason)
        await interaction.response.send_message(
            f"{member.mention} has been timed out for {minutes} minutes.\nReason: {reason}"
        )
    except Exception as e:
        await interaction.response.send_message(f"Failed to timeout {member.mention}. Error: {e}", ephemeral=True)

@client.tree.command(name="deltimeout", description="Remove timeout from a member.")
@app_commands.describe(member="The member to remove timeout from")
async def untimeout(interaction: dc.Interaction, member: dc.Member):
    if not interaction.user.guild_permissions.moderate_members:
        await interaction.response.send_message("You don't have permission to remove timeout.", ephemeral=True)
        return
    try:
        await member.timeout(duration=None)
        await interaction.response.send_message(f"Timeout removed from {member.mention}.")
    except Exception as e:
        await interaction.response.send_message(f"Failed to remove timeout. Error: {e}", ephemeral=True)

@client.tree.command(
    name="changelog",
    description="Send VoraHub changelog embed."
)
async def changelog(
    interaction: dc.Interaction,
    game: str,
    tier: Literal["Free", "Premium"],
    message: str
):

    if not interaction.user.guild_permissions.administrator:
        return await interaction.response.send_message(
            "❌ Command ini **khusus Admin saja**.",
            ephemeral=True
        )

    CHANGELOG_CHANNEL_ID = 1434555092383563777
    BUGREPORT_CHANNEL_ID = 1434769709928284232
    TAG_ID = 1434816903439843359

    changelog_channel = interaction.guild.get_channel(CHANGELOG_CHANNEL_ID)
    if not changelog_channel:
        return await interaction.response.send_message(
            "❌ Changelog channel not found in this server.",
            ephemeral=True
        )

    lines = [line.strip() for line in message.split("|") if line.strip()]

    diff_block = "```diff\n"
    for line in lines:
        if line.startswith("+") or line.startswith("-"):
            diff_block += f"{line}\n"
        else:
            diff_block += f"+ {line}\n"
    diff_block += "```"

    if tier == "Premium":
        tier_text = "**[VoraHub Premium]**"
        embed_color = dc.Color.from_rgb(0, 136, 255)
        tag_message = f"<@&{TAG_ID}>"
    else:
        tier_text = "**[VoraHub Free]**"
        embed_color = dc.Color.from_rgb(0, 136, 255)
        tag_message = f"<@&{TAG_ID}>"

    embed = dc.Embed(
        title="VoraHub Has Been Updated",
        description=f"{tier_text}\n**ChangeLogs — {game}**",
        color=embed_color
    )

    embed.add_field(
        name="",
        value=diff_block,
        inline=False
    )

    embed.add_field(
        name="",
        value=(
            f"**Please re-execute VoraHub**, and use the newest version.\n"
            f"Found a bug? Report it on <#{BUGREPORT_CHANNEL_ID}>\n\n"
            f"💙 Thank you for using **VoraHub {tier}** 💙"
        ),
        inline=False
    )

    if interaction.guild.icon:
        embed.set_thumbnail(url=interaction.guild.icon.url)
    else:
        embed.set_thumbnail(url="https://cdn.discordapp.com/embed/avatars/0.png")

    embed.set_footer(text="VoraHub Official Update • © 2026")

    await changelog_channel.send(tag_message, embed=embed)

    await interaction.response.send_message(
        f"✅ Changelog **{tier}** untuk **{game}** berhasil dikirim ke <#{CHANGELOG_CHANNEL_ID}>.",
        ephemeral=True
    )

@client.tree.command(name="ticketpanel", description="Send the ticket creation panel.")
async def ticketpanel(interaction: dc.Interaction):
    if not interaction.user.guild_permissions.manage_channels:
        return await interaction.response.send_message(
            "❌ You don't have permission to use this command.",
            ephemeral=True
        )

    await interaction.response.defer(ephemeral=True)

    channel = interaction.channel

    await send_ticket_panel(channel)

    await interaction.followup.send(
        "✅ Ticket panel has been sent.",
        ephemeral=True
    )

@client.tree.command(name="add", description="Tambah user ke ticket ini")
@app_commands.describe(user="User yang ingin ditambahkan")
async def add_user(interaction: dc.Interaction, user: dc.Member):

    guild = interaction.guild
    channel = interaction.channel
    staff_role = guild.get_role(STAFF_ROLE_ID)

    # Pastikan staff
    if staff_role not in interaction.user.roles:
        return await interaction.response.send_message(
            "❌ Kamu bukan staff.",
            ephemeral=True
        )

    if channel.id not in active_tickets.values():
        return await interaction.response.send_message(
            "❌ Kamu tidak bisa berinteraksi dengan channel ini karena bukan ticket.",
            ephemeral=True
        )

    # Update permission
    await channel.set_permissions(user, view_channel=True, send_messages=True)

    await interaction.response.send_message(
        f"✅ {user.mention} telah **ditambahkan** ke ticket ini.",
        ephemeral=False
    )

@client.tree.command(name="remove", description="Keluarkan user dari ticket ini")
@app_commands.describe(user="User yang ingin dikeluarkan")
async def remove_user(interaction: dc.Interaction, user: dc.Member):

    guild = interaction.guild
    channel = interaction.channel
    staff_role = guild.get_role(STAFF_ROLE_ID)

    # Pastikan staff
    if staff_role not in interaction.user.roles:
        return await interaction.response.send_message(
            "❌ Kamu bukan staff.",
            ephemeral=True
        )

    if channel.id not in active_tickets.values():
        return await interaction.response.send_message(
            "❌ Kamu tidak bisa berinteraksi dengan channel ini karena bukan ticket.",
            ephemeral=True
        )

    # Jangan keluarkan creator ticket
    for creator_id, ticket_channel_id in active_tickets.items():
        if ticket_channel_id == channel.id and user.id == creator_id:
            return await interaction.response.send_message(
                "❌ Kamu tidak bisa mengeluarkan *pembuat ticket*.",
                ephemeral=True
            )

    await channel.set_permissions(user, overwrite=None)

    await interaction.response.send_message(
        f"🚫 {user.mention} telah **dikeluarkan** dari ticket ini.",
        ephemeral=False
    )

@client.tree.command(name="sales", description="Sales")
@app_commands.describe(
    staff="(Opsional) Staff yang melakukan penjualan - kosongkan untuk lihat leaderboard",
    description="(Opsional) Deskripsi penjualan"
)
async def sales(
    interaction: dc.Interaction,
    staff: dc.Member = None,
    description: str = "Sales"
):
    staff_role = interaction.guild.get_role(STAFF_ROLE_ID)
    helper_role = interaction.guild.get_role(HELPER_ROLE_ID)
    
    # Check if user is staff/helper
    if staff_role not in interaction.user.roles and helper_role not in interaction.user.roles:
        return await interaction.response.send_message(
            "❌ Hanya staff yang bisa menggunakan command ini.",
            ephemeral=True
        )
    
    # If no parameters, show leaderboard
    if staff is None:
        # Get all sales data and sort by total
        leaderboard = []
        for staff_id_str, data in sales_data.items():
            staff_id = int(staff_id_str)
            member = interaction.guild.get_member(staff_id)
            if member:
                leaderboard.append({
                    "member": member,
                    "total": data["total"],
                    "count": len(data["sales"])
                })
        
        # Sort by total sales (descending)
        leaderboard.sort(key=lambda x: x["total"], reverse=True)
        
        if not leaderboard:
            return await interaction.response.send_message(
                "📊 Belum ada data penjualan yang tercatat.",
                ephemeral=True
            )
        
        # Create leaderboard embed
        embed = dc.Embed(
            title="🏆 Leaderboard Penjualan",
            description="Top staff berdasarkan total penjualan",
            color=VORA_BLUE
        )
        
        # Add top 10 to leaderboard
        leaderboard_text = ""
        medals = ["🥇", "🥈", "🥉"]
        for idx, entry in enumerate(leaderboard[:10], 1):
            medal = medals[idx-1] if idx <= 3 else f"**{idx}.**"
            commission = calculate_salary(entry["total"])
            leaderboard_text += (
                f"{medal} {entry['member'].mention}\n"
                f"   💰 Sales: IDR {entry['total']:,} | "
                f"💵 Gaji: IDR {commission:,} | "
                f"📦 {entry['count']} transaksi\n\n"
            )
        
        embed.add_field(
            name="📊 Top Performers",
            value=leaderboard_text or "Tidak ada data",
            inline=False
        )
        
        # Calculate total sales across all staff
        total_all_sales = sum(entry["total"] for entry in leaderboard)
        total_transactions = sum(entry["count"] for entry in leaderboard)
        
        embed.add_field(
            name="📈 Total Keseluruhan",
            value=f"Sales: IDR {total_all_sales:,} | Transaksi: {total_transactions}",
            inline=False
        )
        
        embed.set_footer(text="VoraHub Sales Tracker • Komisi 10%")
        
        await interaction.response.send_message(embed=embed)

@client.tree.command(name="mygaji", description="Lihat total penjualan dan gaji staff")
@app_commands.describe(
    staff="(Opsional) Staff yang ingin dilihat gajinya - kosongkan untuk lihat gaji sendiri"
)
async def mygaji(interaction: dc.Interaction, staff: dc.Member = None):
    # If no staff specified, use the command user
    target_user = staff if staff else interaction.user
    
    # Get sales data for the target user
    staff_sales = get_sales(target_user.id)
    total_sales = staff_sales["total"]
    sales_list = staff_sales["sales"]
    
    # Calculate commission with cap
    gaji = calculate_salary(total_sales)
    is_maxed = gaji >= SALARY_CAP
    
    if total_sales == 0:
        return await interaction.response.send_message(
            f"📊 {target_user.mention} belum memiliki penjualan yang tercatat."
        )
    
    embed = dc.Embed(
        title="💼 Laporan Gaji & Penjualan",
        description=f"Data untuk {target_user.mention}",
        color=VORA_BLUE
    )
    
    embed.add_field(
        name="📈 Total Penjualan",
        value=f"IDR {total_sales:,}",
        inline=True
    )
    
    # Show salary with cap indicator
    salary_text = f"IDR {gaji:,}"
    if is_maxed:
        salary_text += f" 🔴 **MAX**"
    
    embed.add_field(
        name=f"💵 Gaji (Komisi 10%, Max {SALARY_CAP:,})",
        value=salary_text,
        inline=True
    )
    embed.add_field(
        name="🔢 Jumlah Transaksi",
        value=f"{len(sales_list)} transaksi",
        inline=True
    )
    
    # Warning if maxed
    if is_maxed:
        embed.add_field(
            name="⚠️ Peringatan",
            value=f"Gaji sudah mencapai batas maksimal! Tidak bisa claim ticket baru sampai gaji dibayar.",
            inline=False
        )
    
    # Show last 5 transactions
    if len(sales_list) > 0:
        recent_sales = sales_list[-5:]  # Last 5
        sales_text = ""
        for sale in reversed(recent_sales):
            timestamp = datetime.datetime.fromisoformat(sale["timestamp"])
            date_str = timestamp.strftime("%d/%m/%Y %H:%M")
            sales_text += f"• **IDR {sale['amount']:,}** - {sale['description']} ({date_str})\n"
        
        embed.add_field(
            name="📋 Transaksi Terakhir",
            value=sales_text or "Tidak ada transaksi",
            inline=False
        )
    
    embed.set_footer(text="VoraHub Sales Tracker • Data diperbarui real-time")
    
    await interaction.response.send_message(embed=embed)

@client.tree.command(name="gajisudahbayar", description="[ADMIN] Konfirmasi pembayaran gaji staff dan reset sales")
@app_commands.describe(
    staff="Staff yang sudah dibayar gajinya"
)
async def gajisudahbayar(interaction: dc.Interaction, staff: dc.Member):
    # Check if user is admin
    admin_role = interaction.guild.get_role(ADMIN_ROLE_ID)
    
    if admin_role not in interaction.user.roles:
        return await interaction.response.send_message(
            "❌ Hanya admin yang bisa menggunakan command ini.",
            ephemeral=True
        )
    
    # Get staff sales data before reset
    staff_sales = get_sales(staff.id)
    total_sales = staff_sales["total"]
    gaji = calculate_salary(total_sales)
    transaction_count = len(staff_sales["sales"])
    
    if total_sales == 0:
        return await interaction.response.send_message(
            f"❌ {staff.mention} belum memiliki penjualan yang tercatat.",
            ephemeral=True
        )
    
    # Reset sales
    reset_sales(staff.id)
    
    # Send confirmation embed
    embed = dc.Embed(
        title="💰 Gaji Telah Dibayar",
        description=f"Pembayaran gaji untuk {staff.mention} berhasil dikonfirmasi!",
        color=0x00ff00  # Green
    )
    
    embed.add_field(
        name="💵 Gaji yang Dibayar",
        value=f"IDR {gaji:,}",
        inline=True
    )
    embed.add_field(
        name="📈 Total Sales (Sebelum Reset)",
        value=f"IDR {total_sales:,}",
        inline=True
    )
    embed.add_field(
        name="📦 Transaksi",
        value=f"{transaction_count} transaksi",
        inline=True
    )
    embed.add_field(
        name="✅ Status",
        value="Sales telah di-reset ke 0. Staff bisa claim ticket lagi!",
        inline=False
    )
    
    embed.set_footer(text=f"Dibayar oleh {interaction.user.name}")
    embed.timestamp = datetime.datetime.now()
    
    await interaction.response.send_message(embed=embed)
    
    # Notify staff via DM
    try:
        dm_embed = dc.Embed(
            title="💰 Gaji Kamu Telah Dibayar!",
            description=f"Admin telah mengkonfirmasi pembayaran gaji kamu.",
            color=0x00ff00
        )
        dm_embed.add_field(name="💵 Jumlah", value=f"IDR {gaji:,}", inline=True)
        dm_embed.add_field(name="📈 Total Sales", value=f"IDR {total_sales:,}", inline=True)
        dm_embed.add_field(
            name="✅ Status Baru",
            value="Sales kamu sudah di-reset. Kamu bisa claim ticket lagi!",
            inline=False
        )
        dm_embed.set_footer(text="VoraHub Salary System")
        
        await staff.send(embed=dm_embed)
    except:
        # If DM fails, mention in channel
        await interaction.channel.send(
            f"📢 {staff.mention} Gaji kamu sebesar **IDR {gaji:,}** telah dibayar! "
            f"Sales sudah di-reset, kamu bisa claim ticket lagi."
        )

@client.tree.command(name="resetcooldown", description="[ADMIN] Reset cooldown claim ticket untuk staff")
@app_commands.describe(staff="Staff yang ingin di-reset cooldownnya")
async def reset_cooldown(interaction: dc.Interaction, staff: dc.Member):
    """Reset cooldown untuk staff tertentu - hanya bisa digunakan oleh admin"""
    
    # Check if user is admin
    admin_role = interaction.guild.get_role(ADMIN_ROLE_ID)
    if admin_role not in interaction.user.roles:
        await interaction.response.send_message(
            "❌ **Command ini hanya untuk Admin!**\n"
            "Hanya admin yang bisa reset cooldown staff.",
            ephemeral=True
        )
        return
    
    # Check if target is staff
    staff_role = interaction.guild.get_role(STAFF_ROLE_ID)
    helper_role = interaction.guild.get_role(HELPER_ROLE_ID)
    
    if staff_role not in staff.roles and helper_role not in staff.roles:
        await interaction.response.send_message(
            f"❌ {staff.mention} bukan staff atau helper!",
            ephemeral=True
        )
        return
    
    # Get current cooldown status
    on_cooldown, time_left, current_count = is_staff_on_cooldown(staff.id)
    
    # Reset cooldown
    staff_key = str(staff.id)
    if staff_key in staff_cooldowns:
        old_data = staff_cooldowns[staff_key].copy()
        staff_cooldowns[staff_key] = {
            "cycle_start": datetime.datetime.now().isoformat(),
            "claims_in_cycle": 0,
            "exhausted_cooldown_until": None
        }
        save_cooldowns()
        
        # Create embed
        embed = dc.Embed(
            title="🔄 Cooldown Di-Reset",
            description=f"Cooldown untuk {staff.mention} telah berhasil di-reset!",
            color=0x00ff00
        )
        
        # Show previous status
        if on_cooldown and time_left:
            hours = int(time_left.total_seconds() // 3600)
            minutes = int((time_left.total_seconds() % 3600) // 60)
            embed.add_field(
                name="📊 Status Sebelumnya",
                value=f"Cooldown aktif: {hours}j {minutes}m tersisa\nClaim: {current_count}/{COOLDOWN_LIMIT}",
                inline=False
            )
        else:
            embed.add_field(
                name="📊 Status Sebelumnya",
                value=f"Claim: {current_count}/{COOLDOWN_LIMIT}",
                inline=False
            )
        
        embed.add_field(
            name="✅ Status Baru",
            value=f"Claim: 0/{COOLDOWN_LIMIT}\nCooldown: Tidak ada\nStaff bisa claim ticket lagi!",
            inline=False
        )
        
        embed.set_footer(text=f"Di-reset oleh {interaction.user.name}")
        embed.timestamp = datetime.datetime.now()
        
        await interaction.response.send_message(embed=embed)
        
        # Notify staff via DM
        try:
            dm_embed = dc.Embed(
                title="🔄 Cooldown Kamu Di-Reset!",
                description=f"Admin {interaction.user.mention} telah mereset cooldown kamu.",
                color=0x00ff00
            )
            dm_embed.add_field(
                name="✅ Status Baru",
                value=f"Claim: 0/{COOLDOWN_LIMIT}\nKamu bisa claim ticket lagi!",
                inline=False
            )
            dm_embed.set_footer(text="VoraHub Cooldown System")
            
            await staff.send(embed=dm_embed)
        except:
            # If DM fails, mention in channel
            await interaction.channel.send(
                f"📢 {staff.mention} Cooldown kamu telah di-reset oleh admin! Kamu bisa claim ticket lagi."
            )
    else:
        # No cooldown data exists
        await interaction.response.send_message(
            f"ℹ️ {staff.mention} tidak memiliki cooldown aktif.\n"
            f"Staff ini belum pernah claim ticket atau cooldown sudah expired.",
            ephemeral=True
        )

from dotenv import load_dotenv
import os

load_dotenv()

TOKEN = os.getenv("DISCORD_TOKEN")

client.run(TOKEN)


