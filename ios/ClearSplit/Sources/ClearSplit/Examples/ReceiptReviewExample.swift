import SwiftUI

/// Example usage and integration guide for ReceiptReviewView
struct ReceiptReviewExample: View {
    @State private var navigationPath = NavigationPath()
    @State private var showingReceiptReview = false
    @State private var confirmedItems: [ExtractedItem] = []
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                Section("Navigation Examples") {
                    // Example 1: Using NavigationLink
                    NavigationLink("Open Receipt Review (NavigationLink)") {
                        ReceiptReviewView(
                            receiptImage: createSampleImage(),
                            sessionId: 123,
                            onConfirm: { items in
                                handleConfirmedItems(items)
                                navigationPath.removeLast()
                            },
                            onBack: {
                                navigationPath.removeLast()
                            }
                        )
                    }
                    
                    // Example 2: Using Sheet
                    Button("Open Receipt Review (Sheet)") {
                        showingReceiptReview = true
                    }
                }
                
                Section("Confirmed Items") {
                    if confirmedItems.isEmpty {
                        Text("No items confirmed yet")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(confirmedItems) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text("$\(item.totalPrice, specifier: "%.2f")")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Receipt Review Demo")
        }
        .sheet(isPresented: $showingReceiptReview) {
            NavigationView {
                ReceiptReviewView(
                    receiptImage: createSampleImage(),
                    sessionId: 456,
                    onConfirm: { items in
                        handleConfirmedItems(items)
                        showingReceiptReview = false
                    },
                    onBack: {
                        showingReceiptReview = false
                    }
                )
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleConfirmedItems(_ items: [ExtractedItem]) {
        confirmedItems = items
        
        // In a real app, you would save to backend here
        print("Confirmed \(items.count) items:")
        items.forEach { item in
            print("- \(item.name): $\(item.totalPrice)")
        }
        
        // Example: Save to backend
        // Task {
        //     do {
        //         try await api.saveSessionItems(sessionId: sessionId, items: items)
        //     } catch {
        //         print("Error saving items: \(error)")
        //     }
        // }
    }
    
    private func createSampleImage() -> UIImage {
        // Create a simple placeholder image
        let size = CGSize(width: 400, height: 600)
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        
        let context = UIGraphicsGetCurrentContext()!
        
        // White background
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        // Draw "Receipt" text
        let text = "RECEIPT\n\nOrganic Milk    $6.99\nBread           $5.49\nTomatoes        $4.99\n\nTotal:         $17.47"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20),
            .foregroundColor: UIColor.black
        ]
        text.draw(in: CGRect(x: 20, y: 50, width: 360, height: 500), withAttributes: attrs)
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }
}

// MARK: - Integration Guide Comments

/*
 INTEGRATION GUIDE
 =================
 
 ## 1. Basic Usage with NavigationLink
 
 ```swift
 NavigationLink("Review Receipt") {
     ReceiptReviewView(
         receiptImage: receiptImage,
         sessionId: currentSessionId,
         onConfirm: { items in
             handleConfirmedItems(items)
         },
         onBack: {
             // Navigate back
         }
     )
 }
 ```
 
 ## 2. Usage with NavigationPath (iOS 16+)
 
 ```swift
 struct ReceiptReviewDestination: Hashable {
     let image: UIImage
     let sessionId: Int?
 }
 
 NavigationStack(path: $navigationPath) {
     // Your views...
 }
 .navigationDestination(for: ReceiptReviewDestination.self) { destination in
     ReceiptReviewView(
         receiptImage: destination.image,
         sessionId: destination.sessionId,
         onConfirm: { items in
             saveItems(items)
             navigationPath.removeLast()
         },
         onBack: {
             navigationPath.removeLast()
         }
     )
 }
 
 // Navigate to review screen
 navigationPath.append(ReceiptReviewDestination(
     image: receiptImage,
     sessionId: sessionId
 ))
 ```
 
 ## 3. Usage with Sheet Presentation
 
 ```swift
 @State private var showingReview = false
 @State private var receiptImage: UIImage?
 
 Button("Review Receipt") {
     showingReview = true
 }
 .sheet(isPresented: $showingReview) {
     NavigationView {
         ReceiptReviewView(
             receiptImage: receiptImage ?? UIImage(),
             sessionId: sessionId,
             onConfirm: { items in
                 saveItems(items)
                 showingReview = false
             },
             onBack: {
                 showingReview = false
             }
         )
     }
 }
 ```
 
 ## 4. With Real OCR Data
 
 ```swift
 // After OCR extraction
 func handleOCRComplete(items: [ExtractedItem]) {
     navigationPath.append(ReceiptReviewDestination(
         image: receiptImage,
         sessionId: sessionId,
         extractedItems: items  // Pass real OCR data
     ))
 }
 
 ReceiptReviewView(
     receiptImage: receiptImage,
     sessionId: sessionId,
     extractedItems: ocrItems,  // Use OCR data instead of mock
     onConfirm: { items in
         saveToBackend(items)
     },
     onBack: { dismiss() }
 )
 ```
 
 ## 5. Backend Integration
 
 ```swift
 func handleConfirmedItems(_ items: [ExtractedItem]) {
     Task {
         do {
             // Convert to API format
             let apiItems = items.map { item in
                 ShoppingItemCreate(
                     name: item.name,
                     quantity: item.quantity,
                     unitPriceCents: Int(item.price * 100),
                     totalCents: Int(item.totalPrice * 100)
                 )
             }
             
             // Save to backend
             try await api.saveSessionItems(
                 sessionId: sessionId,
                 items: apiItems
             )
             
             // Update local state
             await MainActor.run {
                 self.sessionItems = items
             }
         } catch {
             // Handle error
             errorMessage = "Failed to save items: \(error.localizedDescription)"
         }
     }
 }
 ```
 
 ## 6. With AppState Integration
 
 ```swift
 ReceiptReviewView(
     receiptImage: receiptImage,
     sessionId: sessionId,
     onConfirm: { items in
         Task {
             await appState.saveSessionItems(sessionId: sessionId, items: items)
             navigationPath.removeLast()
         }
     },
     onBack: {
         navigationPath.removeLast()
     }
 )
 ```
 */

// MARK: - Preview
struct ReceiptReviewExample_Previews: PreviewProvider {
    static var previews: some View {
        ReceiptReviewExample()
    }
}
