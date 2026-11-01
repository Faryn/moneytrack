import SwiftUI

struct BudgetView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No budget yet",
                systemImage: "chart.pie",
                description: Text("Your monthly budget and remaining amount will appear here.")
            )
            .navigationTitle("MoneyTrack")
        }
    }
}

#Preview {
    BudgetView()
}
