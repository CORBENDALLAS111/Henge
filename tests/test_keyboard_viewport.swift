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
        let target=CGPoint(x:0.5,y:0.9), request=KeyboardTapRequest(point:CGPoint(x:0.5,y:0.9),began:10)
        func decision(_ time: Double, idle: Bool, mode: String="tap", visible: Bool=false, status: Int32=1, age: Double=0) -> KeyboardTapRequest.Decision {
            request.resolve(now:time,inputActive:true,penIdle:idle,mode:mode,keyboardVisible:visible,focusStatus:status,focusAge:age,focusBounds:CGRect(x:0.4,y:0.8,width:0.2,height:0.2))
        }
        precondition(decision(10.2,idle:false) == .wait, "keyboard must not cancel queued clicks")
        precondition(decision(10.2,idle:false,visible:true) == .wait, "an already open keyboard cannot remap a pending click")
        precondition(decision(10.25,idle:true) == .apply(target,open:true))
        precondition(decision(10.25,idle:true,mode:"manual") == .apply(target,open:false))
        precondition(decision(10.25,idle:true,mode:"text",age:0.2) == .wait, "stale focus cannot open keyboard")
        precondition(decision(10.4,idle:true,mode:"text",age:0.05) == .apply(target,open:true))
        precondition(decision(10.4,idle:true,mode:"text",status:-1) == .wait, "missing accessibility cannot claim an editable field")
        precondition(decision(12.1,idle:true) == .discard)
        precondition(request.resolve(now:10.3,inputActive:false,penIdle:true,mode:"tap",keyboardVisible:false,focusStatus:1,focusAge:0,focusBounds:.zero) == .discard)
        precondition(request.resolve(now:10.4,inputActive:true,penIdle:true,mode:"text",keyboardVisible:false,focusStatus:1,focusAge:0,focusBounds:CGRect(x:0,y:0,width:0.2,height:0.2)) == .wait, "focus in another field cannot turn a button tap into keyboard opening")
        precondition(request.resolve(now:10.4,inputActive:true,penIdle:true,mode:"text",keyboardVisible:false,focusStatus:1,focusAge:0,focusBounds:.zero) == .wait, "unknown field geometry cannot claim a text-field tap")
        print("PASS: keyboard preserves image scale, reveals tapped field, bounds vertical pan and handles invalid geometry")
    }
}
