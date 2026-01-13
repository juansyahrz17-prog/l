import os
import json
import io
import aiohttp
import datetime
import discord as dc
from datetime import timedelta
from discord.ext import commands
from discord import app_commands
from discord import ui, Interaction, ButtonStyle, Embed
from PIL import Image, ImageDraw, ImageFont
from typing import Literal


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

TICKET_PANEL_CHANNEL_ID_X8 = 1443956687433105479
TICKET_CATEGORY_ID_X8 = 1443965063533953104

UNVERIFIED_ROLE_ID = 1434816903439843359
MEMBER_ROLE_ID = 1434816903439843359

VORA_BLUE = 0x3498db
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
TICKET_DATA_FILE = os.path.join(BASE_DIR, "tickets.json")
CLAIMS_FILE = os.path.join(BASE_DIR, "claims.json")
SALES_FILE = os.path.join(BASE_DIR, "sales.json")

# ---------------------------
# LOAD / SAVE TICKETS
# ---------------------------
if not os.path.exists(TICKET_DATA_FILE):
    with open(TICKET_DATA_FILE, "w") as f:
        json.dump({}, f, indent=4)
    active_tickets = {}
else:
    with open(TICKET_DATA_FILE, "r") as f:
        try:
            data = json.load(f)
            active_tickets = {int(k): v for k, v in data.items()}
        except json.JSONDecodeError:
            active_tickets = {}

def save_tickets():
    with open(TICKET_DATA_FILE, "w") as f:
        json.dump({str(k): v for k, v in active_tickets.items()}, f, indent=4)

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

def add_ticket(user_id, channel_id):
    active_tickets[user_id] = channel_id
    save_tickets()

def remove_ticket(user_id):
    if user_id in active_tickets:
        del active_tickets[user_id]
        save_tickets()

ticket_count = max(active_tickets.values(), default=0)

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

class TicketControlView(ui.View):
    def __init__(self, is_premium=False):
        super().__init__(timeout=None)
        self.is_premium = is_premium
        # Claim ticket button
        self.add_item(ui.Button(label="Claim Ticket", style=dc.ButtonStyle.green, emoji="✋", custom_id="claim_ticket"))
        # Close ticket button
        self.add_item(ui.Button(label="Close Ticket", style=dc.ButtonStyle.red, emoji="🔒", custom_id="close_ticket"))
        # Payment button if premium
        if self.is_premium:
            self.add_item(ui.Button(label="💳 Bayar Sekarang", style=dc.ButtonStyle.blurple, custom_id="pay_now"))

    async def interaction_check(self, interaction: Interaction) -> bool:
        cid = interaction.data.get("custom_id")
        if cid == "claim_ticket":
            return await self.claim_ticket_callback(interaction)
        elif cid == "close_ticket":
            return await self.close_ticket_callback(interaction)
        elif cid == "pay_now":
            return await self.pay_now_callback(interaction)
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

        # Find ticket creator
        ticket_creator_id = None
        for uid, cid in active_tickets.items():
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

        await interaction.response.send_message(f"✅ {user.mention} telah **claim** ticket ini! Ticket sekarang hanya terlihat oleh kamu dan pembuat ticket.", ephemeral=False)
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

        # Remove from active tickets and claims
        for uid, cid in list(active_tickets.items()):
            if cid == channel.id:
                del active_tickets[uid]
        save_tickets()
        remove_claim(channel.id)
        await channel.delete()
        return True

    async def pay_now_callback(self, interaction: Interaction):
        if not self.is_premium:
            await interaction.response.send_message("❌ Tidak ada pembayaran di ticket ini.", ephemeral=True)
            return False
        await send_payment_embed(interaction.channel)
        await interaction.response.send_message("📄 Informasi pembayaran dikirim!", ephemeral=True)
        return True

class PaymentActionView(ui.View):
    def __init__(self):
        super().__init__(timeout=None)

    @ui.button(label="📤 Send Proof", style=dc.ButtonStyle.green)
    async def send_proof(self, interaction: Interaction, button: ui.Button):
        await interaction.response.send_message("Silakan **upload bukti transfer** di chat ticket ini.", ephemeral=True)

    @ui.button(label="💳 Open QRIS", style=dc.ButtonStyle.blurple)
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
    global ticket_count
    user = interaction.user
    guild = interaction.guild

    # Cek ticket aktif
    if user.id in active_tickets:
        ch = guild.get_channel(active_tickets[user.id])
        ch_mention = ch.mention if ch else "tidak ditemukan"
        return await interaction.response.send_message(
            f"⚠ Kamu masih punya ticket aktif di {ch_mention}.", ephemeral=True
        )

    ticket_count += 1
    category_id = TICKET_CATEGORY_ID_X8 if "x8" in category_name.lower() else TICKET_CATEGORY_ID
    category = guild.get_channel(category_id)
    staff_role = guild.get_role(STAFF_ROLE_ID)
    helper_role = guild.get_role(HELPER_ROLE_ID)
    channel_name = f"{'x8-' if 'x8' in category_name.lower() else ''}ticket-{ticket_count:04}"

    ticket_channel = await guild.create_text_channel(
        name=channel_name,
        category=category,
        overwrites={
            guild.default_role: dc.PermissionOverwrite(view_channel=False),
            user: dc.PermissionOverwrite(view_channel=True, send_messages=True),
            staff_role: dc.PermissionOverwrite(view_channel=True, send_messages=True),
            helper_role: dc.PermissionOverwrite(view_channel=True, send_messages=True)
        }
    )
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

    await ticket_channel.send(
        content=" ".join(mentions),
        embed=embed,
        view=TicketControlView(is_premium=is_premium)
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
        embed.set_footer(text="VoraHub Official • © 2025")
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
    embed.set_footer(text="VoraHub Official • © 2025")
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
            "name": "Verifikasi",
            "channel_id": 1443599341850857562,
            "message_id": 1443640023516708884,
            "embed": get_verif_embed(),
            "view": VerifView,
            "tag": None
        }
    ]

    async def on_ready(self):
        print(f"Logged in as {self.user}")
        try:
            synced = await self.tree.sync()
            print(f"✅ Globally synced {len(synced)} slash commands.")
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

    async def auto_edit_panel(self, channel_id, message_id, embed, view, tag=None):
        channel = self.get_channel(channel_id)
        if not channel:
            print(f"[PANEL] Channel {channel_id} tidak ditemukan.")
            return
        content = tag if tag else None
        try:
            msg = await channel.fetch_message(message_id)
            await msg.edit(content=content, embed=embed, view=view)
            print(f"[PANEL] Message {message_id} berhasil di-edit.")
        except dc.NotFound:
            await channel.send(content=content, embed=embed, view=view)
            print(f"[PANEL] Message {message_id} tidak ditemukan, baru dibuat.")
        except Exception as e:
            print(f"[PANEL] Gagal edit/send message {message_id}: {e}")

    
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
                    # Assuming premium tickets are in TICKET_CATEGORY_ID
                    if message.channel.category_id == TICKET_CATEGORY_ID:
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

    embed.set_footer(text="VoraHub Official Update • © 2025")

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

@client.tree.command(name="sales", description="Catat penjualan premium")
@app_commands.describe(
    staff="Staff yang melakukan penjualan",
    amount="Jumlah penjualan (IDR)",
    description="Deskripsi penjualan (opsional)"
)
async def sales(
    interaction: dc.Interaction,
    staff: dc.Member,
    amount: int,
    description: str = "Premium Sale"
):
    # Only staff can record sales
    staff_role = interaction.guild.get_role(STAFF_ROLE_ID)
    helper_role = interaction.guild.get_role(HELPER_ROLE_ID)
    
    if staff_role not in interaction.user.roles and helper_role not in interaction.user.roles:
        return await interaction.response.send_message(
            "❌ Hanya staff yang bisa mencatat penjualan.",
            ephemeral=True
        )
    
    # Add the sale
    add_sale(staff.id, amount, description)
    
    # Get updated stats
    staff_sales = get_sales(staff.id)
    total = staff_sales["total"]
    count = len(staff_sales["sales"])
    
    embed = dc.Embed(
        title="💰 Penjualan Tercatat",
        description=f"Penjualan berhasil dicatat untuk {staff.mention}",
        color=VORA_BLUE
    )
    embed.add_field(name="Jumlah", value=f"IDR {amount:,}", inline=True)
    embed.add_field(name="Deskripsi", value=description, inline=True)
    embed.add_field(name="Total Penjualan", value=f"IDR {total:,}", inline=False)
    embed.add_field(name="Jumlah Transaksi", value=f"{count} transaksi", inline=False)
    embed.set_footer(text="VoraHub Sales Tracker")
    
    await interaction.response.send_message(embed=embed)

@client.tree.command(name="mygaji", description="Lihat total penjualan dan gaji kamu")
async def mygaji(interaction: dc.Interaction):
    # Get sales data for the user
    staff_sales = get_sales(interaction.user.id)
    total_sales = staff_sales["total"]
    sales_list = staff_sales["sales"]
    
    # Calculate commission (example: 10% of total sales)
    COMMISSION_RATE = 0.10
    gaji = int(total_sales * COMMISSION_RATE)
    
    if total_sales == 0:
        return await interaction.response.send_message(
            "📊 Kamu belum memiliki penjualan yang tercatat.",
            ephemeral=True
        )
    
    embed = dc.Embed(
        title="💼 Laporan Gaji & Penjualan",
        description=f"Data untuk {interaction.user.mention}",
        color=VORA_BLUE
    )
    
    embed.add_field(
        name="📈 Total Penjualan",
        value=f"IDR {total_sales:,}",
        inline=True
    )
    embed.add_field(
        name="💵 Gaji (Komisi 10%)",
        value=f"IDR {gaji:,}",
        inline=True
    )
    embed.add_field(
        name="🔢 Jumlah Transaksi",
        value=f"{len(sales_list)} transaksi",
        inline=True
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
    
    await interaction.response.send_message(embed=embed, ephemeral=True)

from dotenv import load_dotenv
import os

load_dotenv()

TOKEN = os.getenv("DISCORD_TOKEN")

client.run(TOKEN)



