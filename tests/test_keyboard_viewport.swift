import Foundation
import CoreGraphics

@main struct KeyboardViewportTests {
    static func main() {
        let base=CGRect(x:0,y:0,width:1000,height:700)
        let keyboard=CGRect(x:0,y:400,width:1000,height:300)
        precondition(KeyboardViewport.frame(base,keyboard:.zero,focus:.zero,pan:0)==base)
        for y in [0.0,0.2,0.5,0.9,1.0] {
            let focus=CGPoint(x:0.8,y:y)
            let shown=KeyboardViewport.frame(base,keyboard:keyboard,focus:focus,pan:0)
            precondition(shown.size==base.size && shown.minX==base.minX, "keyboard must not shrink or move horizontally")
            precondition(shown.minY + CGFloat(y)*base.height <= keyboard.minY-58, "tapped field remains above keyboard and handle")
            precondition(shown.minY<=0 && shown.maxY>=keyboard.minY-58)
        }
        let top=KeyboardViewport.frame(base,keyboard:keyboard,focus:CGPoint(x:0.5,y:0.9),pan:10000)
        let bottom=KeyboardViewport.frame(base,keyboard:keyboard,focus:CGPoint(x:0.5,y:0.9),pan:-10000)
        precondition(top.minY==0 && bottom.maxY==342)
        let small=CGRect(x:8,y:10,width:500,height:280)
        precondition(KeyboardViewport.frame(small,keyboard:keyboard,focus:.zero,pan:0)==small)
        let invalid=KeyboardViewport.frame(base,keyboard:keyboard,focus:CGPoint(x:0,y:CGFloat.nan),pan:CGFloat.nan)
        precondition(invalid.minY.isFinite && invalid.size==base.size)
        print("PASS: keyboard preserves image scale, reveals tapped field, bounds vertical pan and handles invalid geometry")
    }
}
