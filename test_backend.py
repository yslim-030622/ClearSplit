#!/usr/bin/env python3
"""
Comprehensive Backend Test Script
Tests all major functionality including Shopping Sessions
"""

import requests
import json
import time
from datetime import date

BASE_URL = "http://localhost:8000"

# Colors for terminal output
class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    BLUE = '\033[94m'
    YELLOW = '\033[93m'
    END = '\033[0m'

tests_passed = 0
tests_failed = 0

def test(name, method, endpoint, data=None, headers=None, expected_status=200):
    """Run a single test"""
    global tests_passed, tests_failed
    
    print(f"\n{Colors.BLUE}Testing: {name}{Colors.END}")
    
    url = f"{BASE_URL}{endpoint}"
    
    try:
        if method == "GET":
            response = requests.get(url, headers=headers, json=data)
        elif method == "POST":
            response = requests.post(url, headers=headers, json=data)
        elif method == "PUT":
            response = requests.put(url, headers=headers, json=data)
        elif method == "DELETE":
            response = requests.delete(url, headers=headers, json=data)
        
        if response.status_code == expected_status:
            print(f"{Colors.GREEN}✓ PASSED{Colors.END} (HTTP {response.status_code})")
            tests_passed += 1
            try:
                print(json.dumps(response.json(), indent=2))
            except:
                print(response.text)
            return response
        else:
            print(f"{Colors.RED}✗ FAILED{Colors.END} (Expected {expected_status}, got {response.status_code})")
            tests_failed += 1
            print(response.text)
            return None
            
    except Exception as e:
        print(f"{Colors.RED}✗ ERROR: {str(e)}{Colors.END}")
        tests_failed += 1
        return None

def main():
    global tests_passed, tests_failed
    
    print(f"\n{'='*60}")
    print(f"Testing ClearSplit Backend at {BASE_URL}")
    print(f"{'='*60}\n")
    
    # 1. Health Check
    print("\n=== 1. HEALTH CHECK ===")
    test("Health endpoint", "GET", "/health")
    
    # 2. Authentication
    print("\n=== 2. AUTHENTICATION ===")
    
    # Create unique test user
    test_email = f"test_{int(time.time())}@example.com"
    test_password = "SecurePass123!"
    
    print(f"\nSigning up with: {test_email}")
    signup_response = test(
        "User signup",
        "POST",
        "/auth/signup",
        data={"email": test_email, "password": test_password},
        expected_status=200
    )
    
    if not signup_response:
        print(f"{Colors.RED}Signup failed. Cannot continue tests.{Colors.END}")
        return
    
    signup_data = signup_response.json()
    access_token = signup_data["access_token"]
    user_id = signup_data["user"]["id"]
    
    print(f"\n{Colors.GREEN}User ID: {user_id}{Colors.END}")
    print(f"{Colors.GREEN}Token: {access_token[:30]}...{Colors.END}")
    
    headers = {"Authorization": f"Bearer {access_token}"}
    
    # Test /auth/me
    test("Get current user", "GET", "/auth/me", headers=headers)
    
    # 3. Groups
    print("\n=== 3. GROUPS ===")
    
    group_response = test(
        "Create group",
        "POST",
        "/groups",
        data={"name": "Test Grocery Group", "currency": "USD"},
        headers=headers
    )
    
    if not group_response:
        print(f"{Colors.RED}Group creation failed. Cannot continue tests.{Colors.END}")
        return
    
    group_data = group_response.json()
    group_id = group_data["id"]
    membership_id = group_data["user_membership_id"]
    
    print(f"\n{Colors.GREEN}Group ID: {group_id}{Colors.END}")
    print(f"{Colors.GREEN}Membership ID: {membership_id}{Colors.END}")
    
    # List groups
    test("List user groups", "GET", "/groups", headers=headers)
    
    # Get group members
    test("List group members", "GET", f"/groups/{group_id}/members", headers=headers)
    
    # 4. Shopping Sessions
    print("\n=== 4. SHOPPING SESSIONS ===")
    
    session_response = test(
        "Create shopping session",
        "POST",
        f"/groups/{group_id}/shopping-sessions",
        data={
            "title": "Costco Trip",
            "shopping_date": str(date.today()),
            "paid_by_membership_id": membership_id
        },
        headers=headers
    )
    
    if not session_response:
        print(f"{Colors.RED}Session creation failed. Cannot continue tests.{Colors.END}")
        return
    
    session_data = session_response.json()
    session_id = session_data["id"]
    
    print(f"\n{Colors.GREEN}Session ID: {session_id}{Colors.END}")
    
    # List shopping sessions
    test("List shopping sessions", "GET", f"/groups/{group_id}/shopping-sessions", headers=headers)
    
    # Get specific session
    test("Get shopping session details", "GET", f"/shopping-sessions/{session_id}", headers=headers)
    
    # Set participants
    test(
        "Set session participants",
        "PUT",
        f"/shopping-sessions/{session_id}/participants",
        data={"membership_ids": [membership_id]},
        headers=headers
    )
    
    # 5. Shopping Items
    print("\n=== 5. SHOPPING ITEMS ===")
    
    # Create item 1: Milk
    item1_response = test(
        "Create item: Milk",
        "POST",
        f"/shopping-sessions/{session_id}/items",
        data={
            "name": "Milk",
            "quantity": 2,
            "unit_price_cents": 349,
            "total_cents": 698
        },
        headers=headers
    )
    
    if item1_response:
        item1_id = item1_response.json()["id"]
        print(f"{Colors.GREEN}Item 1 ID: {item1_id}{Colors.END}")
    
    # Create item 2: Bread
    item2_response = test(
        "Create item: Bread",
        "POST",
        f"/shopping-sessions/{session_id}/items",
        data={
            "name": "Bread",
            "quantity": 1,
            "total_cents": 299
        },
        headers=headers
    )
    
    if item2_response:
        item2_id = item2_response.json()["id"]
        print(f"{Colors.GREEN}Item 2 ID: {item2_id}{Colors.END}")
    
    # Create item 3: Eggs (for testing split calculation with remainder)
    item3_response = test(
        "Create item: Eggs (for split testing)",
        "POST",
        f"/shopping-sessions/{session_id}/items",
        data={
            "name": "Eggs",
            "quantity": 1,
            "total_cents": 500  # $5.00 - easy to split
        },
        headers=headers
    )
    
    if item3_response:
        item3_id = item3_response.json()["id"]
        print(f"{Colors.GREEN}Item 3 ID: {item3_id}{Colors.END}")
    
    # 6. Split Calculations
    print("\n=== 6. SPLIT CALCULATIONS ===")
    
    if item1_response:
        print(f"\n{Colors.YELLOW}Setting sharers for Milk ($6.98) - 1 person{Colors.END}")
        test(
            "Set sharers for Milk",
            "PUT",
            f"/items/{item1_id}/sharers",
            data={"membership_ids": [membership_id]},
            headers=headers
        )
    
    if item3_response:
        print(f"\n{Colors.YELLOW}Setting sharers for Eggs ($5.00) - 1 person{Colors.END}")
        test(
            "Set sharers for Eggs",
            "PUT",
            f"/items/{item3_id}/sharers",
            data={"membership_ids": [membership_id]},
            headers=headers
        )
    
    # 7. Final Verification
    print("\n=== 7. FINAL VERIFICATION ===")
    
    final_response = test(
        "Get complete session with all items and splits",
        "GET",
        f"/shopping-sessions/{session_id}",
        headers=headers
    )
    
    if final_response:
        final_data = final_response.json()
        items_count = len(final_data.get("items", []))
        print(f"\n{Colors.GREEN}✓ Session contains {items_count} items{Colors.END}")
        
        # Show split summary
        print(f"\n{Colors.YELLOW}Split Summary:{Colors.END}")
        for item in final_data.get("items", []):
            print(f"  - {item['name']}: ${item['total_cents']/100:.2f}")
            for split in item.get("splits", []):
                print(f"    → ${split['share_cents']/100:.2f} per person")
    
    # Test Summary
    print(f"\n{'='*60}")
    print(f"TEST SUMMARY")
    print(f"{'='*60}")
    print(f"Tests Passed: {Colors.GREEN}{tests_passed}{Colors.END}")
    print(f"Tests Failed: {Colors.RED}{tests_failed}{Colors.END}\n")
    
    if tests_failed == 0:
        print(f"{Colors.GREEN}✓ All tests passed!{Colors.END}\n")
        return 0
    else:
        print(f"{Colors.RED}✗ Some tests failed.{Colors.END}\n")
        return 1

if __name__ == "__main__":
    exit(main())

