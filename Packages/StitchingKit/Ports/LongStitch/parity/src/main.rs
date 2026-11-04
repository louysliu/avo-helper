use longstitch::session::StitchSession;
fn main() {
    let args: Vec<_> = std::env::args().skip(1).collect();
    let width = args[0].parse::<u32>().unwrap();
    let height = args[1].parse::<u32>().unwrap();
    let mut s = StitchSession::new(width,height,0,0,0.01).unwrap();
    for path in &args[2..] {
        let mut pixels = std::fs::read(path).unwrap();
        for px in pixels.chunks_exact_mut(4) {px.swap(0,2);}
        println!("{path}: {:?}",s.push_bgra(&pixels,None,0.15,0.0,true));
    }
}
