# ClearSplit iOS App — Design & Functionality Showcase

> **"Clearly split with your friends."**

ClearSplit is a native iOS app built for people who share expenses — roommates splitting groceries, friends going out for dinner, or travel groups pooling costs. It takes the awkwardness out of "who owes what" by tracking every item, every receipt, and every payment in one place. No spreadsheets, no mental math, no guesswork.

This document walks through the actual iOS screens, explains what each one does, and shows how the frontend connects to the FastAPI backend behind the scenes.

---

## Tech at a Glance

| Layer | Stack |
|-------|-------|
| **iOS App** | SwiftUI (MVVM) · Zero external dependencies · Keychain-based auth |
| **Backend** | FastAPI · PostgreSQL 16 · SQLAlchemy (async) · JWT auth |
| **Infra** | Docker Compose (local) · Azure Container Apps (staging) · AWS S3 (receipts) |

---

## 1. Welcome & Login

<p align="center">
  <img src="images/screenshots/02_login.png" width="300" alt="Login screen" />
</p>

The first thing you see when you open ClearSplit. Clean, focused, no distractions — just your email and password.

The app's tagline sits right below the logo: *"clearly split with your friends"*. It sets the tone for the whole experience.

**What happens when you tap "Log In":**

- The iOS `LoginViewModel` validates your input and fires a `POST /auth/login` request.
- The backend authenticates against a bcrypt-hashed password with timing-safe comparison (so even failed logins don't leak information about whether the account exists).
- On success, you get back a JWT access token (15-min TTL) and a refresh token (30-day TTL, rotated on each use). Both are stored securely in the iOS Keychain — not UserDefaults, not in memory.
- The app then calls `GET /auth/me` to pull your full profile and bootstraps the main view.

If you close and reopen the app later, it silently restores your session from the Keychain without asking you to log in again.

---

## 2. Create Account

<p align="center">
  <img src="images/screenshots/01_create_account.png" width="300" alt="Create Account screen" />
</p>

New here? The sign-up form collects just what's needed — name, username, email, and password. No phone number, no social login clutter.

**What's validated before the request even leaves your phone:**

- Username must be alphanumeric (underscores and hyphens allowed)
- Password needs at least 8 characters
- Confirm password must match

**On the backend side (`POST /auth/signup`):**

- Username and email are normalized to lowercase and checked for uniqueness.
- Password is hashed with bcrypt before storage — the plaintext never touches the database.
- A signup rate limit (5 requests per 5 minutes per IP) prevents abuse.
- On success, the response includes tokens and user data, so you're logged in immediately — no "check your email" step.

---

## 3. My Groups

<p align="center">
  <img src="images/screenshots/03_my_groups.png" width="300" alt="My Groups screen" />
</p>

This is your home base after logging in. Every group you belong to shows up here as a card, with the member count and a quick status — "All settled up" means nobody owes anyone. That's the goal.

**How it works:**

- `GET /groups` returns all groups where you're a member (owner, member, or viewer).
- Each card shows the group name and member count, pulled from the memberships table.
- The "All settled up" badge comes from the balance data — when every member's net balance is zero, the group is settled.
- Pull down to refresh. Tap a group to dive into its details. The blue "Create New Group" button at the bottom creates a new one via `POST /groups`, and you're automatically added as the owner.

The bottom tab bar gives you three main areas: **Groups**, **Friends**, and **Profile**. Groups is where you'll spend most of your time.

---

## 4. Group Overview

<p align="center">
  <img src="images/screenshots/04_group_overview.png" width="300" alt="Group Overview screen" />
</p>

Tap into a group and you get the full picture at a glance. The blue hero card at the top shows the **total spent across all shopping trips** — a number computed by summing every shopping session's items.

Below that, you see:

- **Members** — who's in the group, with avatars built from initials. The "You" badge marks your own entry. The "+ Add" button lets owners invite new members by username.
- **Shopping Sessions** — where the actual expense tracking happens. Each shopping trip (grocery run, dinner out, etc.) is its own session.
- **Balances & Settlement** — the bottom line: who owes who, and how to settle up.

**Backend integration:**

- Group details come from `GET /groups/{id}` with membership data from `GET /groups/{id}/members`.
- The total spent is calculated client-side by aggregating shopping session totals.
- Only owners can add members (role-based access enforced on both client and server).

---

## 5. Shopping Sessions

<p align="center">
  <img src="images/screenshots/05_shopping_sessions.png" width="300" alt="Shopping Sessions screen" />
</p>

Each shopping session represents one trip or one bill. The card shows:

- **Session title** and **total amount**
- **Date** of the shopping trip
- **Number of items** added
- **Who paid** — because that matters for splitting

The blue "+" button in the top right creates a new session via `POST /groups/{id}/shopping-sessions`. You pick a title, set who paid, and optionally add a date. The payer is always the creator — you can only create sessions where you're the one who paid.

**Backend flow:**

- `GET /groups/{id}/shopping-sessions` lists all sessions with their items, participants, and receipt metadata eagerly loaded in one query.
- Sessions have three statuses: **Active** (editable), **Finalized** (locked for settlement), and **Settled** (all payments complete).
- Swipe left on a session to delete it — cascades through items, splits, and receipts.

---

## 6. Session Detail — Participants & Receipts

<p align="center">
  <img src="images/screenshots/06_session_participants.png" width="300" alt="Session Participants screen" />
</p>

Inside a session, you get the full breakdown. The blue header shows the **total amount** and **who paid**.

Below that:

- **Participants** — the people sharing this bill. Tap "Edit" to change who's included via `PUT /shopping-sessions/{id}/participants`. Only the payer can modify participants.
- **Receipts** — upload a photo of the receipt. The backend stores it in AWS S3 with presigned URLs (15-minute TTL) for secure, temporary access. There's even an OCR pipeline (`POST /receipts/{id}/extract-items`) that can pull item names and prices from the receipt image using Tesseract.
- **Items** — the actual things purchased, with prices and per-person shares.

The receipt thumbnail you see is fetched via `GET /receipts/{id}/download-url`, which returns a short-lived S3 presigned URL. The image itself never passes through the API server on download.

---

## 7. Session Detail — Items & Splits

<p align="center">
  <img src="images/screenshots/07_session_items.png" width="300" alt="Session Items screen" />
</p>

This is where the splitting actually happens. Each item card shows:

- **Item name** and **total price**
- **Quantity** and unit breakdown
- **Who's sharing it** — shown as name badges
- **Your share** — calculated and shown in the bottom-right of each card

In this example, "Tacos Del Mal Shrimp" costs $14.98 and is shared by Eunshin Park and You — so your share is $7.49. Same logic for the salad ($6.25 each) and the beverage ($0.99 each).

**How splits are calculated:**

The backend uses **deterministic integer arithmetic** to avoid floating-point rounding errors. When $14.98 (1498 cents) is split between 2 people:
- Each person gets `1498 / 2 = 749 cents` ($7.49)
- If there's a remainder (say splitting $14.99 between 2), the extra cent goes to the first person in the list — the payer gets preference for the remainder.

This is handled by `PUT /items/{id}/sharers` on the backend, which recalculates splits every time you change who's sharing an item. The edit (pencil) and delete (trash) icons let you modify items inline.

---

## 8. Friends

<p align="center">
  <img src="images/screenshots/08_friends.png" width="300" alt="Friends screen" />
</p>

The Friends tab is your social layer. At the top, you'll see **Friend Requests** — incoming requests with accept (checkmark) and decline (X) buttons.

Below that is your **My Friends** list. In this screenshot, it's empty — but once you accept requests or add friends, they'll show up here with search functionality.

The blue info banner at the bottom explains why friends matter: *"Add friends to easily create groups and split expenses together."*

**Backend integration:**

- `GET /friends/requests/incoming` fetches pending requests.
- `POST /friends/requests/{id}/accept` or `/decline` handles the response.
- `GET /friends` lists accepted friendships with optional search (`?q=...`).
- Friendships are stored as normalized pairs (lower UUID first) to prevent duplicates — you can't have two friendship records between the same two people.

---

## 9. Add Friend

<p align="center">
  <img src="images/screenshots/09_add_friend_modal.png" width="300" alt="Add Friend modal" />
</p>

Tap the "+ Add" button and this form slides in. You can find friends by **email/username** or by **User ID** — toggle between the two input modes at the top.

Type in their identifier, hit "Send Request", and a friend request is created via `POST /friends/requests`. The other person will see it in their Friend Requests section.

**What the backend checks:**

- You can't send a request to yourself
- You can't send a duplicate request to someone you've already friended or have a pending request with
- The identifier is normalized (lowercased) before lookup
- Rate limiting prevents spam

---

## 10. Profile

<p align="center">
  <img src="images/screenshots/10_profile.png" width="300" alt="Profile screen" />
</p>

The Profile tab shows your identity and activity summary:

- **Avatar** with your initials (generated client-side from your first and last name)
- **Full name** and **member since** date
- **Edit Profile** button for updating your details
- **Stats cards**: number of groups you belong to, and total amount split across all groups
- **Account Information**: your registered email
- **Settings**: app configuration and logout

The stats are computed client-side from the groups and session data already loaded in the `AppState`. The "2 Groups" and "$29.47 Total Split" reflect real data from the backend — it's not a static mock.

---

## 11. Balances & Settlement

<p align="center">
  <img src="images/screenshots/11_balances_settlement.png" width="300" alt="Balances & Settlement screen" />
</p>

This is where everything comes together. The settlement screen answers the only question that matters: **who owes who, and how much?**

**Individual Balances** shows each member's net position:
- "You" owes **$14.73** (shown in red)
- Eunshin Park gets back **+$14.73** (shown in green)

**Suggested Payments** shows the simplest way to settle up:
- You pay Eunshin Park $14.73. One payment. Done.

The "Mark as Paid" button records the payment via `POST /groups/{id}/settlement-payments` with `auto_confirm: true`.

**How balances are calculated on the backend (`GET /groups/{id}/balances`):**

The settlement service aggregates across all data sources:
1. **Expense payments** — what each person paid
2. **Expense splits** — what each person owes
3. **Shopping session items** — item-level shares from all active sessions

It computes a net balance per member (paid minus owed), then runs a **transfer minimization algorithm** to suggest the fewest payments needed to settle everyone up. The light blue explainer card at the bottom walks users through how it works — no finance degree required.

---

## 12. Add Member

<p align="center">
  <img src="images/screenshots/12_add_member_modal.png" width="300" alt="Add Member modal" />
</p>

Group owners can add new members through this modal. Type a username, hit Search, and the backend runs a preview check via `POST /groups/{id}/members/preview` — it tells you whether the user exists, whether they're already in the group, and their current role if applicable.

If everything checks out, confirm and the member is added via `POST /groups/{id}/members` with a default "member" role.

**Security considerations:**

- Only group owners can add members (enforced server-side with role checks)
- The preview endpoint is rate-limited to prevent username/email enumeration
- Member search uses case-insensitive matching

---

## Design Philosophy

A few things that shaped how these screens look and feel:

**Minimal, card-based layout** — Every piece of information lives in a card. Cards create visual hierarchy without needing heavy borders or backgrounds. They also translate well to different screen sizes.

**Blue as the primary accent** — The brand blue (`#4A6CF7`-ish) is used sparingly: CTAs, active tabs, hero cards, and the logo. Everything else is neutral whites and grays. This keeps the interface calm — fitting for an app that deals with money.

**Progressive disclosure** — The group overview doesn't dump everything on you. It shows the summary first (total spent, members), and lets you drill into sessions, items, and settlements one level at a time.

**Real data, always** — Every number on screen comes from the backend. There are no hardcoded placeholders. The $29.47 total, the $14.73 balance, the item prices — all computed from actual database records through the API.

**Zero external dependencies on iOS** — The entire app is built with Foundation and SwiftUI. No Alamofire, no Kingfisher, no third-party UI kit. This keeps the binary small, builds fast, and avoids supply chain risk.

---

## Full User Flow

Here's how a typical session plays out, end to end:

```
Sign Up / Log In
       |
   My Groups ──────────── Create New Group
       |
  Group Overview
       |
   ┌───┼──────────────┐
   |   |               |
Members  Shopping    Balances &
   |    Sessions     Settlement
   |       |              |
Add     Create         View who
Member  Session       owes what
           |              |
      Add Items      Mark as Paid
      Set Sharers
      Upload Receipt
      (OCR Extract)
```

Every arrow in this flow is a real API call. Every screen is a real SwiftUI view. Every number is computed from PostgreSQL through FastAPI.

---

## API Endpoints by Screen

For reference, here's a mapping of every screen to the backend endpoints it talks to:

| Screen | Endpoints |
|--------|-----------|
| Login | `POST /auth/login`, `GET /auth/me` |
| Sign Up | `POST /auth/signup` |
| My Groups | `GET /groups` |
| Group Overview | `GET /groups/{id}`, `GET /groups/{id}/members`, `GET /groups/{id}/shopping-sessions` |
| Shopping Sessions | `GET /groups/{id}/shopping-sessions`, `POST /groups/{id}/shopping-sessions` |
| Session Detail | `GET /shopping-sessions/{id}`, `PUT /shopping-sessions/{id}/participants` |
| Items & Splits | `POST /shopping-sessions/{id}/items`, `PUT /items/{id}/sharers`, `PATCH /items/{id}` |
| Receipts | `POST /shopping-sessions/{id}/receipt`, `GET /receipts/{id}/download-url`, `POST /receipts/{id}/extract-items` |
| Friends | `GET /friends`, `GET /friends/requests/incoming`, `GET /friends/requests/outgoing` |
| Add Friend | `POST /friends/requests`, `POST /friends/requests/{id}/accept` |
| Profile | `GET /auth/me` (cached in AppState) |
| Balances | `GET /groups/{id}/balances` |
| Settlement | `POST /groups/{id}/settlement-payments`, `POST /settlement-payments/{id}/confirm` |
| Add Member | `POST /groups/{id}/members/preview`, `POST /groups/{id}/members` |

---

*Built with SwiftUI and FastAPI. Designed for clarity. Engineered for correctness.*
