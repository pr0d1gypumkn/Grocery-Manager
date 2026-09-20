import SwiftUI

struct LaunchScreenView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                Color.black
                    .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.0, green: 0.75, blue: 0.91),
                        Color(red: 0.0, green: 0.78, blue: 0.70)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }

            VStack(spacing: 20) {
                Image("LaunchIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 18, x: 0, y: 10)

                Text("Grocery Manager")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(colorScheme == .dark ? .white : .white)
                    .tracking(0.4)
            }
        }
    }
}

#Preview {
    LaunchScreenView()
}
