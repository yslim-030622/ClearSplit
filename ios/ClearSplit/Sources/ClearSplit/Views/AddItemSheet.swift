import SwiftUI

struct AddItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var itemName = ""
    @State private var unitPriceText = ""
    @State private var quantity = 1
    @State private var selectedParticipants: Set<UUID> = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showDiscardAlert = false
    @State private var formErrors: [String: String] = [:]
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case name, price
    }
    
    let appState: AppState
    let sessionId: UUID
    let groupId: UUID
    let onAdded: (ShoppingSession) -> Void
    
    @State private var loadedSession: ShoppingSession?
    @State private var groupMemberships: [Membership] = []
    
    var participants: [ShoppingSessionParticipant] {
        loadedSession?.participants ?? []
    }
    
    var unitPrice: Double {
        Double(unitPriceText) ?? 0
    }
    
    var itemTotal: Double {
        unitPrice * Double(quantity)
    }
    
    var isDirty: Bool {
        !itemName.trimmingCharacters(in: .whitespaces).isEmpty ||
        !unitPriceText.isEmpty ||
        quantity != 1 ||
        !selectedParticipants.isEmpty
    }
    
    var isValid: Bool {
        !itemName.trimmingCharacters(in: .whitespaces).isEmpty &&
        unitPrice > 0 &&
        quantity >= 1 &&
        !selectedParticipants.isEmpty &&
        formErrors.isEmpty
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Item Details Card
                    VStack(alignment: .leading, spacing: 20) {
                        // Item Name
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 4) {
                                Text("Item Name")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.gray900)
                                Text("*")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.red500)
                            }
                            
                            TextField("e.g., Organic Milk, Apples, Bread", text: $itemName)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(.gray900)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 14)
                                .frame(height: 48)
                                .background(inputBackground(for: "name"))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(inputBorder(for: "name"), lineWidth: inputBorderWidth(for: "name"))
                                )
                                .overlay(
                                    Group {
                                        if focusedField == .name && formErrors["name"] == nil {
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.blue500.opacity(0.1), lineWidth: 4)
                                                .padding(-2)
                                        }
                                    }
                                )
                                .focused($focusedField, equals: .name)
                                .onChange(of: itemName) { oldValue, newValue in
                                    if formErrors["name"] != nil {
                                        validateField("name", value: newValue)
                                    }
                                }
                            
                            if let error = formErrors["name"] {
                                Text(error)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(.red600)
                            } else {
                                Text("Give this item a clear name")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(.gray500)
                            }
                        }
                        
                        // Unit Price
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 4) {
                                Text("Unit Price")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.gray900)
                                Text("*")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.red500)
                            }
                            
                            HStack(spacing: 8) {
                                Text("$")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.gray700)
                                    .padding(.leading, 12)
                                
                                TextField("0.00", text: $unitPriceText)
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.gray900)
                                    .keyboardType(.decimalPad)
                                    .focused($focusedField, equals: .price)
                                    .onChange(of: unitPriceText) { oldValue, newValue in
                                        if formErrors["unitPrice"] != nil {
                                            validateField("unitPrice", value: newValue)
                                        }
                                    }
                            }
                            .padding(.vertical, 12)
                            .frame(height: 48)
                            .background(inputBackground(for: "unitPrice"))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(inputBorder(for: "unitPrice"), lineWidth: inputBorderWidth(for: "unitPrice"))
                            )
                            .overlay(
                                Group {
                                    if focusedField == .price && formErrors["unitPrice"] == nil {
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.blue500.opacity(0.1), lineWidth: 4)
                                            .padding(-2)
                                    }
                                }
                            )
                            
                            if let error = formErrors["unitPrice"] {
                                Text(error)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(.red600)
                            } else {
                                Text("Price per item or unit")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(.gray500)
                            }
                        }
                        
                        // Quantity
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 4) {
                                Text("Quantity")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.gray900)
                                Text("*")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.red500)
                            }
                            
                            HStack(spacing: 0) {
                                Button(action: {
                                    if quantity > 1 {
                                        quantity -= 1
                                    }
                                }) {
                                    Image(systemName: "minus")
                                        .font(.system(size: 20, weight: .regular))
                                        .foregroundColor(quantity <= 1 ? .gray400 : .gray700)
                                        .frame(width: 48, height: 48)
                                }
                                .disabled(quantity <= 1)
                                
                                Text("\(quantity)")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.gray900)
                                    .frame(width: 44)
                                
                                Button(action: {
                                    if quantity < 999 {
                                        quantity += 1
                                    }
                                }) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 20, weight: .regular))
                                        .foregroundColor(quantity >= 999 ? .gray400 : .gray700)
                                        .frame(width: 48, height: 48)
                                }
                                .disabled(quantity >= 999)
                            }
                            .background(Color.gray100)
                            .cornerRadius(12)
                            
                            Text("Number of items")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.gray500)
                        }
                        
                        // Item Total
                        HStack {
                            Text("Item Total")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blue900)
                            
                            Spacer()
                            
                            Text(formatCurrency(cents: Int(itemTotal * 100), currency: "USD"))
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.blue900)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .background(Color.blue50)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue200, lineWidth: 1)
                        )
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray200, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
                    
                    // Participants Card
                    VStack(alignment: .leading, spacing: 16) {
                        // Header
                        HStack(spacing: 8) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.gray700)
                            Text("Split Between")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.gray900)
                            Text("*")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.red500)
                        }
                        
                        Text("Select who will share this item")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.gray500)
                        
                        // Participants List
                        if participants.isEmpty {
                            Text("No participants available. Set participants first.")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.gray500)
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(participants) { participant in
                                    AddItemParticipantRow(
                                        participant: participant,
                                        membership: groupMemberships.first(where: { $0.id == participant.membershipId }),
                                        isSelected: selectedParticipants.contains(participant.membershipId),
                                        onToggle: {
                                            if selectedParticipants.contains(participant.membershipId) {
                                                selectedParticipants.remove(participant.membershipId)
                                            } else {
                                                selectedParticipants.insert(participant.membershipId)
                                            }
                                            formErrors.removeValue(forKey: "participants")
                                        }
                                    )
                                }
                            }
                            .padding(.top, 4)
                        }
                        
                        // Selection Summary
                        if !selectedParticipants.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.blue600)
                                Text(selectedParticipants.count == 1
                                     ? "Only you will pay for this item"
                                     : "\(selectedParticipants.count) people will split this item")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.blue700)
                            }
                        }
                        
                        // Error Message
                        if let error = formErrors["participants"] {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.red600)
                                Text(error)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(.red600)
                            }
                        }
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(formErrors["participants"] != nil ? Color.red600 : Color.gray200, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
                }
                .padding(16)
            }
            .background(Color.gray50)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if isDirty {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.blue600)
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Add Item")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.gray900)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSaving {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Saving...")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.blue600)
                    } else {
                        Button("Save") {
                            Task {
                                await saveItem()
                            }
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(isValid ? .blue600 : .gray400)
                        .disabled(!isValid)
                    }
                }
            }
            .alert("Discard Changes?", isPresented: $showDiscardAlert) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    dismiss()
                }
            } message: {
                Text("Your item will not be saved.")
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                await loadSession()
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func inputBackground(for field: String) -> Color {
        if formErrors[field] != nil {
            return .red50
        }
        if focusedField == (field == "name" ? Field.name : Field.price) {
            return .white
        }
        return .gray100
    }
    
    private func inputBorder(for field: String) -> Color {
        if formErrors[field] != nil {
            return .red300
        }
        if focusedField == (field == "name" ? Field.name : Field.price) {
            return .blue500
        }
        return .clear
    }
    
    private func inputBorderWidth(for field: String) -> CGFloat {
        if formErrors[field] != nil {
            return 1
        }
        if focusedField == (field == "name" ? Field.name : Field.price) {
            return 2
        }
        return 0
    }
    
    private func loadSession() async {
        do {
            // Load session
            loadedSession = try await appState.shoppingService.getSession(sessionId: sessionId)
            
            // Load group memberships to get user names
            groupMemberships = try await appState.groupsService.listMemberships(groupId: groupId)
            
            // Pre-select first participant (usually current user)
            if let session = loadedSession,
               !session.participants.isEmpty {
                if let firstParticipant = session.participants.first {
                    selectedParticipants.insert(firstParticipant.membershipId)
                }
            }
        } catch {
            errorMessage = "Failed to load session details."
        }
    }
    
    private func validateField(_ field: String, value: String) {
        formErrors.removeValue(forKey: field)
        
        switch field {
        case "name":
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                formErrors["name"] = "Item name is required"
            } else if trimmed.count > 100 {
                formErrors["name"] = "Name must be less than 100 characters"
            }
        case "unitPrice":
            if let price = Double(value) {
                if price <= 0 {
                    formErrors["unitPrice"] = "Price must be greater than $0"
                } else if price > 999999.99 {
                    formErrors["unitPrice"] = "Price exceeds maximum"
                }
            } else if !value.isEmpty {
                formErrors["unitPrice"] = "Enter a valid price"
            }
        default:
            break
        }
    }
    
    private func validateForm() -> Bool {
        formErrors.removeAll()
        
        // Validate name
        let trimmedName = itemName.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty {
            formErrors["name"] = "Item name is required"
        } else if trimmedName.count > 100 {
            formErrors["name"] = "Name must be less than 100 characters"
        }
        
        // Validate unit price
        if unitPrice <= 0 {
            formErrors["unitPrice"] = "Price must be greater than $0"
        } else if unitPrice > 999999.99 {
            formErrors["unitPrice"] = "Price exceeds maximum"
        }
        
        // Validate quantity
        if quantity < 1 {
            formErrors["quantity"] = "Quantity must be at least 1"
        } else if quantity > 999 {
            formErrors["quantity"] = "Quantity exceeds maximum"
        }
        
        // Validate participants
        if selectedParticipants.isEmpty {
            formErrors["participants"] = "Select at least one person to split with"
        }
        
        return formErrors.isEmpty
    }
    
    private func saveItem() async {
        guard validateForm() else { return }
        
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        
        do {
            // 1. Create the item
            let totalCents = Int((itemTotal * 100).rounded())
            let unitPriceCents = Int((unitPrice * 100).rounded())
            
            let itemRequest = ShoppingItemCreate(
                name: itemName.trimmingCharacters(in: .whitespaces),
                quantity: quantity,
                unitPriceCents: unitPriceCents,
                totalCents: totalCents
            )
            
            let createdItem = try await appState.shoppingService.createItem(
                sessionId: sessionId,
                request: itemRequest
            )
            
            // 2. Set sharers
            let sharersRequest = SharersSetRequest(membershipIds: Array(selectedParticipants))
            _ = try await appState.shoppingService.setSharers(
                itemId: createdItem.id,
                request: sharersRequest
            )
            
            // 3. Refresh session
            let updated = try await appState.refreshShoppingSession(sessionId: sessionId, groupId: groupId)
            onAdded(updated)
            dismiss()
        } catch {
            errorMessage = "Failed to add item. Please try again."
        }
    }
}

// MARK: - Add Item Participant Row

struct AddItemParticipantRow: View {
    let participant: ShoppingSessionParticipant
    let membership: Membership?
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.clear : Color.gray300, lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color.blue600 : Color.white)
                        )
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                // Avatar
                ZStack {
                    Circle()
                        .fill(avatarGradient)
                        .frame(width: 32, height: 32)
                    
                    Text(displayInitial)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                // Name
                Text(displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray900)
                
                Spacer()
            }
            .frame(height: 56)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.blue50 : Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue200 : Color.gray200, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var displayName: String {
        if let membership = membership,
           let user = membership.user {
            return "\(user.firstName) \(user.lastName)"
        }
        return "Member"
    }
    
    private var displayInitial: String {
        if let membership = membership,
           let user = membership.user {
            return String(user.firstName.prefix(1)).uppercased()
        }
        return String(participant.membershipId.uuidString.prefix(1)).uppercased()
    }
    
    private var avatarGradient: LinearGradient {
        let colors = [
            [Color(hex: "60A5FA"), Color(hex: "2563EB")], // Blue
            [Color(hex: "C084FC"), Color(hex: "9333EA")], // Purple
            [Color(hex: "4ADE80"), Color(hex: "16A34A")], // Green
            [Color(hex: "FB923C"), Color(hex: "EA580C")], // Orange
            [Color(hex: "F472B6"), Color(hex: "DB2777")], // Pink
            [Color(hex: "818CF8"), Color(hex: "4F46E5")]  // Indigo
        ]
        
        let hash = participant.membershipId.uuidString.hashValue
        let index = abs(hash) % colors.count
        let colorPair = colors[index]
        
        return LinearGradient(
            colors: colorPair,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
