"""Tests for friends endpoints."""

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.jwt import create_access_token
from app.models.friendship import Friendship, FriendshipStatus
from app.models.user import User
from app.tests.conftest import create_test_user


def _auth_header(user: User) -> dict[str, str]:
    token = create_access_token(user.id, user.email)
    return {"Authorization": f"Bearer {token}"}


async def _create_user(
    session: AsyncSession,
    *,
    email: str,
    username: str,
    first_name: str = "Test",
    last_name: str = "User",
) -> User:
    user = create_test_user(
        email=email,
        username=username,
        first_name=first_name,
        last_name=last_name,
    )
    session.add(user)
    await session.flush()
    return user


@pytest.mark.asyncio
async def test_send_friend_request_success(client: AsyncClient, session: AsyncSession):
    sender = await _create_user(
        session,
        email="sender@example.com",
        username="sender",
        first_name="Sender",
    )
    receiver = await _create_user(
        session,
        email="receiver@example.com",
        username="receiver",
        first_name="Receiver",
    )

    response = await client.post(
        "/friends/requests",
        headers=_auth_header(sender),
        json={"to_user_id": str(receiver.id)},
    )

    assert response.status_code == 201, response.text
    payload = response.json()
    assert payload["status"] == "pending"
    assert payload["requested_by_user_id"] == str(sender.id)
    assert payload["friend"]["id"] == str(receiver.id)
    assert payload["friend"]["username"] == "receiver"
    assert "email" not in payload["friend"]

    row_result = await session.execute(select(Friendship).where(Friendship.id == payload["id"]))
    friendship = row_result.scalar_one_or_none()
    assert friendship is not None
    assert friendship.status == FriendshipStatus.PENDING


@pytest.mark.asyncio
async def test_send_friend_request_self_fails(client: AsyncClient, session: AsyncSession):
    user = await _create_user(
        session,
        email="self@example.com",
        username="selfuser",
    )

    response = await client.post(
        "/friends/requests",
        headers=_auth_header(user),
        json={"to_user_id": str(user.id)},
    )

    assert response.status_code == 400
    assert "yourself" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_duplicate_friend_request_fails(client: AsyncClient, session: AsyncSession):
    sender = await _create_user(
        session,
        email="dup-sender@example.com",
        username="dupsender",
    )
    receiver = await _create_user(
        session,
        email="dup-receiver@example.com",
        username="dupreceiver",
    )

    first = await client.post(
        "/friends/requests",
        headers=_auth_header(sender),
        json={"to_user_id": str(receiver.id)},
    )
    assert first.status_code == 201, first.text

    duplicate = await client.post(
        "/friends/requests",
        headers=_auth_header(sender),
        json={"to_user_id": str(receiver.id)},
    )
    assert duplicate.status_code == 409


@pytest.mark.asyncio
async def test_accept_only_by_receiver(client: AsyncClient, session: AsyncSession):
    sender = await _create_user(
        session,
        email="accept-sender@example.com",
        username="acceptsender",
    )
    receiver = await _create_user(
        session,
        email="accept-receiver@example.com",
        username="acceptreceiver",
    )

    request_response = await client.post(
        "/friends/requests",
        headers=_auth_header(sender),
        json={"to_user_id": str(receiver.id)},
    )
    assert request_response.status_code == 201, request_response.text
    friendship_id = request_response.json()["id"]

    sender_accept = await client.post(
        f"/friends/requests/{friendship_id}/accept",
        headers=_auth_header(sender),
    )
    assert sender_accept.status_code == 403

    receiver_accept = await client.post(
        f"/friends/requests/{friendship_id}/accept",
        headers=_auth_header(receiver),
    )
    assert receiver_accept.status_code == 200
    assert receiver_accept.json()["status"] == "accepted"


@pytest.mark.asyncio
async def test_decline_only_by_receiver(client: AsyncClient, session: AsyncSession):
    sender = await _create_user(
        session,
        email="decline-sender@example.com",
        username="declinesender",
    )
    receiver = await _create_user(
        session,
        email="decline-receiver@example.com",
        username="declinereceiver",
    )

    request_response = await client.post(
        "/friends/requests",
        headers=_auth_header(sender),
        json={"to_user_id": str(receiver.id)},
    )
    assert request_response.status_code == 201, request_response.text
    friendship_id = request_response.json()["id"]

    sender_decline = await client.post(
        f"/friends/requests/{friendship_id}/decline",
        headers=_auth_header(sender),
    )
    assert sender_decline.status_code == 403

    receiver_decline = await client.post(
        f"/friends/requests/{friendship_id}/decline",
        headers=_auth_header(receiver),
    )
    assert receiver_decline.status_code == 200
    assert receiver_decline.json()["status"] == "declined"


@pytest.mark.asyncio
async def test_list_friends_returns_only_accepted(client: AsyncClient, session: AsyncSession):
    current = await _create_user(
        session,
        email="list-current@example.com",
        username="listcurrent",
    )
    accepted_friend = await _create_user(
        session,
        email="list-accepted@example.com",
        username="listaccepted",
    )
    pending_friend = await _create_user(
        session,
        email="list-pending@example.com",
        username="listpending",
    )
    declined_friend = await _create_user(
        session,
        email="list-declined@example.com",
        username="listdeclined",
    )

    accepted_request = await client.post(
        "/friends/requests",
        headers=_auth_header(current),
        json={"to_user_id": str(accepted_friend.id)},
    )
    accepted_id = accepted_request.json()["id"]
    accepted_response = await client.post(
        f"/friends/requests/{accepted_id}/accept",
        headers=_auth_header(accepted_friend),
    )
    assert accepted_response.status_code == 200

    pending_request = await client.post(
        "/friends/requests",
        headers=_auth_header(pending_friend),
        json={"to_user_id": str(current.id)},
    )
    assert pending_request.status_code == 201

    declined_request = await client.post(
        "/friends/requests",
        headers=_auth_header(current),
        json={"to_user_id": str(declined_friend.id)},
    )
    declined_id = declined_request.json()["id"]
    declined_response = await client.post(
        f"/friends/requests/{declined_id}/decline",
        headers=_auth_header(declined_friend),
    )
    assert declined_response.status_code == 200

    friends_response = await client.get(
        "/friends",
        headers=_auth_header(current),
    )
    assert friends_response.status_code == 200
    rows = friends_response.json()
    assert len(rows) == 1
    assert rows[0]["friend"]["id"] == str(accepted_friend.id)
    assert rows[0]["status"] == "accepted"


@pytest.mark.asyncio
async def test_search_friends_filters_by_query(client: AsyncClient, session: AsyncSession):
    current = await _create_user(
        session,
        email="search-current@example.com",
        username="searchcurrent",
    )
    anna = await _create_user(
        session,
        email="search-anna@example.com",
        username="anna_friend",
        first_name="Anna",
    )
    ben = await _create_user(
        session,
        email="search-ben@example.com",
        username="benfriend",
        first_name="Benjamin",
    )

    for friend in [anna, ben]:
        request_response = await client.post(
            "/friends/requests",
            headers=_auth_header(current),
            json={"to_user_id": str(friend.id)},
        )
        assert request_response.status_code == 201, request_response.text
        friendship_id = request_response.json()["id"]
        accept_response = await client.post(
            f"/friends/requests/{friendship_id}/accept",
            headers=_auth_header(friend),
        )
        assert accept_response.status_code == 200

    filtered = await client.get(
        "/friends",
        headers=_auth_header(current),
        params={"q": "ANN"},
    )
    assert filtered.status_code == 200
    rows = filtered.json()
    assert len(rows) == 1
    assert rows[0]["friend"]["id"] == str(anna.id)


@pytest.mark.asyncio
async def test_reverse_pending_request_auto_accepts(client: AsyncClient, session: AsyncSession):
    user_a = await _create_user(
        session,
        email="auto-a@example.com",
        username="autoa",
    )
    user_b = await _create_user(
        session,
        email="auto-b@example.com",
        username="autob",
    )

    first = await client.post(
        "/friends/requests",
        headers=_auth_header(user_a),
        json={"to_user_id": str(user_b.id)},
    )
    assert first.status_code == 201
    assert first.json()["status"] == "pending"

    reverse = await client.post(
        "/friends/requests",
        headers=_auth_header(user_b),
        json={"to_user_id": str(user_a.id)},
    )
    assert reverse.status_code == 201
    assert reverse.json()["status"] == "accepted"


@pytest.mark.asyncio
async def test_declined_friendship_can_be_resent(client: AsyncClient, session: AsyncSession):
    user_a = await _create_user(
        session,
        email="retry-a@example.com",
        username="retrya",
    )
    user_b = await _create_user(
        session,
        email="retry-b@example.com",
        username="retryb",
    )

    first = await client.post(
        "/friends/requests",
        headers=_auth_header(user_a),
        json={"to_user_id": str(user_b.id)},
    )
    assert first.status_code == 201
    friendship_id = first.json()["id"]

    declined = await client.post(
        f"/friends/requests/{friendship_id}/decline",
        headers=_auth_header(user_b),
    )
    assert declined.status_code == 200
    assert declined.json()["status"] == "declined"

    resent = await client.post(
        "/friends/requests",
        headers=_auth_header(user_a),
        json={"to_user_id": str(user_b.id)},
    )
    assert resent.status_code == 201
    assert resent.json()["status"] == "pending"
    assert resent.json()["requested_by_user_id"] == str(user_a.id)


@pytest.mark.asyncio
async def test_send_friend_request_by_identifier_username(
    client: AsyncClient,
    session: AsyncSession,
):
    sender = await _create_user(
        session,
        email="identifier-sender@example.com",
        username="identifier_sender",
    )
    receiver = await _create_user(
        session,
        email="identifier-receiver@example.com",
        username="identifier_receiver",
    )

    response = await client.post(
        "/friends/requests",
        headers=_auth_header(sender),
        json={"identifier": receiver.username},
    )

    assert response.status_code == 201, response.text
    payload = response.json()
    assert payload["friend"]["id"] == str(receiver.id)
    assert payload["friend"]["username"] == receiver.username
    assert payload["status"] == "pending"


@pytest.mark.asyncio
async def test_send_friend_request_by_identifier_email(
    client: AsyncClient,
    session: AsyncSession,
):
    sender = await _create_user(
        session,
        email="identifier-email-sender@example.com",
        username="identifier_email_sender",
    )
    receiver = await _create_user(
        session,
        email="identifier-email-receiver@example.com",
        username="identifier_email_receiver",
    )

    response = await client.post(
        "/friends/requests",
        headers=_auth_header(sender),
        json={"identifier": receiver.email},
    )

    assert response.status_code == 201, response.text
    payload = response.json()
    assert payload["friend"]["id"] == str(receiver.id)
    assert payload["friend"]["username"] == receiver.username
    assert payload["status"] == "pending"


@pytest.mark.asyncio
async def test_list_incoming_friend_requests(client: AsyncClient, session: AsyncSession):
    current = await _create_user(
        session,
        email="incoming-current@example.com",
        username="incoming_current",
    )
    sender = await _create_user(
        session,
        email="incoming-sender@example.com",
        username="incoming_sender",
    )
    outgoing_target = await _create_user(
        session,
        email="incoming-outgoing-target@example.com",
        username="incoming_outgoing_target",
    )
    accepted_user = await _create_user(
        session,
        email="incoming-accepted@example.com",
        username="incoming_accepted",
    )

    pending_incoming = await client.post(
        "/friends/requests",
        headers=_auth_header(sender),
        json={"to_user_id": str(current.id)},
    )
    assert pending_incoming.status_code == 201, pending_incoming.text

    pending_outgoing = await client.post(
        "/friends/requests",
        headers=_auth_header(current),
        json={"to_user_id": str(outgoing_target.id)},
    )
    assert pending_outgoing.status_code == 201, pending_outgoing.text

    accepted_request = await client.post(
        "/friends/requests",
        headers=_auth_header(current),
        json={"to_user_id": str(accepted_user.id)},
    )
    assert accepted_request.status_code == 201, accepted_request.text
    accepted_id = accepted_request.json()["id"]
    accepted_response = await client.post(
        f"/friends/requests/{accepted_id}/accept",
        headers=_auth_header(accepted_user),
    )
    assert accepted_response.status_code == 200, accepted_response.text

    incoming_response = await client.get(
        "/friends/requests/incoming",
        headers=_auth_header(current),
    )
    assert incoming_response.status_code == 200, incoming_response.text
    rows = incoming_response.json()
    assert len(rows) == 1
    assert rows[0]["friend"]["id"] == str(sender.id)
    assert rows[0]["status"] == "pending"


@pytest.mark.asyncio
async def test_list_outgoing_friend_requests(client: AsyncClient, session: AsyncSession):
    current = await _create_user(
        session,
        email="outgoing-current@example.com",
        username="outgoing_current",
    )
    sender = await _create_user(
        session,
        email="outgoing-sender@example.com",
        username="outgoing_sender",
    )
    outgoing_target = await _create_user(
        session,
        email="outgoing-target@example.com",
        username="outgoing_target",
    )

    pending_incoming = await client.post(
        "/friends/requests",
        headers=_auth_header(sender),
        json={"to_user_id": str(current.id)},
    )
    assert pending_incoming.status_code == 201, pending_incoming.text

    pending_outgoing = await client.post(
        "/friends/requests",
        headers=_auth_header(current),
        json={"to_user_id": str(outgoing_target.id)},
    )
    assert pending_outgoing.status_code == 201, pending_outgoing.text

    outgoing_response = await client.get(
        "/friends/requests/outgoing",
        headers=_auth_header(current),
    )
    assert outgoing_response.status_code == 200, outgoing_response.text
    rows = outgoing_response.json()
    assert len(rows) == 1
    assert rows[0]["friend"]["id"] == str(outgoing_target.id)
    assert rows[0]["status"] == "pending"


@pytest.mark.asyncio
async def test_delete_friendship_removes_friend_edge(client: AsyncClient, session: AsyncSession):
    current = await _create_user(
        session,
        email="delete-current@example.com",
        username="delete_current",
    )
    friend = await _create_user(
        session,
        email="delete-friend@example.com",
        username="delete_friend",
    )

    request_response = await client.post(
        "/friends/requests",
        headers=_auth_header(current),
        json={"to_user_id": str(friend.id)},
    )
    assert request_response.status_code == 201, request_response.text
    friendship_id = request_response.json()["id"]

    accept_response = await client.post(
        f"/friends/requests/{friendship_id}/accept",
        headers=_auth_header(friend),
    )
    assert accept_response.status_code == 200, accept_response.text

    delete_response = await client.delete(
        f"/friends/{friendship_id}",
        headers=_auth_header(current),
    )
    assert delete_response.status_code == 200, delete_response.text

    friends_response = await client.get(
        "/friends",
        headers=_auth_header(current),
    )
    assert friends_response.status_code == 200, friends_response.text
    assert friends_response.json() == []
