use long_screen::{
    source::{Frame, FrameSource, Frames, MediaInfo, SourceError},
    value::Obj,
    Control, Options, Progress,
};
use std::{
    ffi::{c_char, c_void, CStr, CString},
    path::PathBuf,
};
#[repr(C)]
pub struct LSFrame {
    time: f64,
    duration: f64,
    width: usize,
    height: usize,
}
type Reset = extern "C" fn(*mut c_void) -> i32;
type Next = extern "C" fn(*mut c_void, *mut LSFrame, *mut *const u8, *mut usize) -> i32;
struct Source {
    info: MediaInfo,
    reset: Reset,
    next: Next,
    context: usize,
}
impl FrameSource for Source {
    fn info(&self) -> &MediaInfo {
        &self.info
    }
    fn frames(&mut self) -> Result<Frames<'_>, SourceError> {
        if (self.reset)(self.context as *mut c_void) != 0 {
            return Err(SourceError("Decoder reset failed".into()));
        }
        let mut index = 0;
        Ok(Box::new(std::iter::from_fn(move || {
            let mut f = LSFrame {
                time: 0.0,
                duration: 0.0,
                width: 0,
                height: 0,
            };
            let mut ptr = std::ptr::null();
            let mut len = 0;
            let status = (self.next)(self.context as *mut c_void, &mut f, &mut ptr, &mut len);
            if status == 0 {
                return None;
            }
            if status < 0 {
                return Some(Err(SourceError("Decoder failed or cancelled".into())));
            }
            if ptr.is_null()
                || f.width.checked_mul(f.height).and_then(|n| n.checked_mul(4)) != Some(len)
            {
                return Some(Err(SourceError("Invalid RGBA frame".into())));
            }
            let rgba = unsafe { std::slice::from_raw_parts(ptr, len) }.to_vec();
            let frame = Frame {
                index,
                time: f.time,
                duration: f.duration,
                width: f.width,
                height: f.height,
                rgba,
            };
            index += 1;
            Some(Ok(frame))
        })))
    }
}
type Callback = extern "C" fn(*mut c_void, f64, *const c_char) -> i32;
#[no_mangle]
pub unsafe extern "C" fn ls_string_free(p: *mut c_char) {
    if !p.is_null() {
        drop(CString::from_raw(p));
    }
}
#[no_mangle]
pub unsafe extern "C" fn ls_run(
    width: usize,
    height: usize,
    duration: f64,
    reset: Reset,
    next: Next,
    out: *const c_char,
    max_pixels: usize,
    budget: usize,
    cb: Option<Callback>,
    ctx: *mut c_void,
) -> *mut c_char {
    let result = std::panic::catch_unwind(|| -> Result<serde_json::Value, String> {
        if out.is_null()
            || width == 0
            || height == 0
            || budget < 64 * 1024 * 1024
            || max_pixels == 0
        {
            return Err("Invalid input or working budget".into());
        }
        let out = PathBuf::from(CStr::from_ptr(out).to_str().map_err(|e| e.to_string())?);
        let info = MediaInfo::from_js(
            Obj::new()
                .with("name", "video")
                .with("width", width)
                .with("height", height)
                .with("duration", duration)
                .with("noise", 10.0),
        );
        let mut source = Source {
            info,
            reset,
            next,
            context: ctx as usize,
        };
        let control = Control::new();
        let context = ctx as usize;
        let disk_exceeded = std::sync::atomic::AtomicBool::new(false);
        let mut observer = |p: &Progress| {
            let disk_bytes: u64 = std::fs::read_dir(out.join("tiles"))
                .into_iter()
                .flatten()
                .filter_map(Result::ok)
                .filter_map(|e| e.metadata().ok())
                .map(|m| m.len())
                .sum();
            if disk_bytes > budget as u64 {
                disk_exceeded.store(true, std::sync::atomic::Ordering::Relaxed);
                control.stop();
            }

            if let Some(cb) = cb {
                let msg = CString::new(format!("{}: {}", p.phase, p.message)).unwrap_or_default();
                let phase = match p.phase.as_str() {
                    "scanning" => 0.0,
                    "solving" => 1.0,
                    "optimizing" => 2.0,
                    "rendering" => 3.0,
                    "revealing" => 4.0,
                    "framing" => 5.0,
                    "pyramid" => 6.0,
                    _ => 7.0,
                };
                if cb(
                    context as *mut c_void,
                    (phase + p.fraction) / 8.0,
                    msg.as_ptr(),
                ) != 0
                {
                    control.stop();
                }
            }
        };
        let mut options = Options::default();
        options.store_budget = Some(budget / 8);
        options.settings.memory_mb = (budget / 4) as f64 / 1048576.0;
        options.spill_dir = Some(out.join("tiles"));
        let result = long_screen::run(&mut source, &options, &mut observer, &control)
            .map_err(|e| e.to_string())?;
        let mut images = Vec::new();
        let mut warnings: Vec<String> = result
            .diagnostics()
            .iter()
            .filter(|d| d.severity != "info")
            .map(|d| d.message.clone())
            .collect();
        if disk_exceeded.load(std::sync::atomic::Ordering::Relaxed) {
            warnings.push("Temporary tile disk budget exceeded; retained available output".into());
        }
        let mut partial = result.status() != "complete"
            || disk_exceeded.load(std::sync::atomic::Ordering::Relaxed);
        let mut pixels = 0usize;
        for (i, c) in result.prints().into_iter().enumerate() {
            let (w, h) = result.canvas_size(&c.id).map_err(|e| e.to_string())?;
            let n = (w as usize)
                .checked_mul(h as usize)
                .ok_or("Canvas size overflow")?;
            if pixels.saturating_add(n) > max_pixels {
                warnings.push(format!("Canvas {} skipped: output pixel budget", c.id));
                partial = true;
                continue;
            }
            pixels += n;
            let name = format!("long-screen-{}.png", i);
            let path = out.join(&name);
            let file = std::fs::File::create(&path).map_err(|e| e.to_string())?;
            result
                .write_png(&c.id, std::io::BufWriter::new(file))
                .map_err(|e| e.to_string())?;
            images.push(serde_json::json!({"file":name,"width":w,"height":h}));
        }
        if let Some(e) = result.error() {
            warnings.push(e.into());
        }
        Ok(serde_json::json!({"images":images,"warnings":warnings,"partial":partial}))
    });
    let value = match result {
        Ok(Ok(v)) => v,
        Ok(Err(e)) => serde_json::json!({"error":e}),
        Err(_) => serde_json::json!({"error":"Rust engine panic"}),
    };
    CString::new(value.to_string()).unwrap().into_raw()
}
