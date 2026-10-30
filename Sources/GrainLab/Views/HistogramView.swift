import SwiftUI

public struct HistogramView: View {
    let luma: [Float]
    let red: [Float]
    let green: [Float]
    let blue: [Float]
    
    @State private var selectedChannel: Channel = .rgb
    
    enum Channel: String, CaseIterable, Identifiable {
        case rgb = "RGB"
        case luma = "Luma"
        
        var id: String { rawValue }
    }
    
    public init(luma: [Float], red: [Float], green: [Float], blue: [Float]) {
        self.luma = luma
        self.red = red
        self.green = green
        self.blue = blue
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("HISTOGRAM")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Picker("", selection: $selectedChannel) {
                    ForEach(Channel.allCases) { ch in
                        Text(ch.rawValue).tag(ch)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }
            
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(height: 70)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    
                    if selectedChannel == .luma {
                        channelPath(values: luma, width: w, height: h)
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.6), Color.white.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                        channelPath(values: luma, width: w, height: h)
                            .stroke(Color.white.opacity(0.8), lineWidth: 1.2)
                    } else {
                        // RGB layered with blend mode
                        channelPath(values: red, width: w, height: h)
                            .stroke(Color.red.opacity(0.75), lineWidth: 1.0)
                        channelPath(values: green, width: w, height: h)
                            .stroke(Color.green.opacity(0.75), lineWidth: 1.0)
                        channelPath(values: blue, width: w, height: h)
                            .stroke(Color.blue.opacity(0.75), lineWidth: 1.0)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(height: 70)
            }
        }
    }
    
    private func channelPath(values: [Float], width: CGFloat, height: CGFloat) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        
        let step = width / CGFloat(values.count - 1)
        path.move(to: CGPoint(x: 0, y: height))
        
        for (i, val) in values.enumerated() {
            let x = CGFloat(i) * step
            let y = height - (CGFloat(min(max(val, 0), 1)) * height)
            if i == 0 {
                path.addLine(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        path.addLine(to: CGPoint(x: width, y: height))
        path.closeSubpath()
        return path
    }
}
