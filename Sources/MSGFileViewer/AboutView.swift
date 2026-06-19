// MSGFileViewer - About View
// Shows developer and application information

import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            
            Text("MSG File Viewer")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Version 1.0")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.horizontal, 40)
            
            VStack(spacing: 8) {
                Text("A native macOS app for reading Microsoft Outlook .msg files completely offline.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            
            Divider()
                .padding(.horizontal, 40)
            
            VStack(spacing: 4) {
                Text("Developed by")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Abhishek Dadhich")
                    .font(.headline)
                Text("dadhich@gmail.com")
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                    .textSelection(.enabled)
            }
            
            Spacer()
            
            Text("© 2026 Abhishek Dadhich. All rights reserved.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(width: 360, height: 320)
    }
}
