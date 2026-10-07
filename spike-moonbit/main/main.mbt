///|
/// Spike: MoonBit owning the game loop and scene logic, raylib doing the raster work.
///
/// This is the architectural probe for the AI-native engine — everything an agent
/// would reason about (layout, animation, timing, capture) lives here in MoonBit;
/// only the draw calls cross into C.

///|
#borrow(title)
extern "c" fn mbg_init(title : String) = "mbg_init"
extern "c" fn mbg_close() = "mbg_close"
extern "c" fn mbg_should_close() -> Int = "mbg_should_close"
extern "c" fn mbg_begin_frame() = "mbg_begin_frame"
extern "c" fn mbg_end_frame() = "mbg_end_frame"
extern "c" fn mbg_clear(r : Int, g : Int, b : Int) = "mbg_clear"
extern "c" fn mbg_time() -> Double = "mbg_time"
extern "c" fn mbg_fps() -> Int = "mbg_fps"
extern "c" fn mbg_rect(
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  radius : Double,
  r : Int,
  g : Int,
  b : Int
) = "mbg_rect"
extern "c" fn mbg_circle(
  x : Double,
  y : Double,
  radius : Double,
  r : Int,
  g : Int,
  b : Int
) = "mbg_circle"
extern "c" fn mbg_line(
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
  thick : Double,
  r : Int,
  g : Int,
  b : Int
) = "mbg_line"

///|
#borrow(text)
extern "c" fn mbg_text(
  text : String,
  cx : Double,
  cy : Double,
  size : Double,
  r : Int,
  g : Int,
  b : Int
) -> Double = "mbg_text"
extern "c" fn mbg_key_pressed(key : Int) -> Int = "mbg_key_pressed"

///|
#borrow(path)
extern "c" fn mbg_screenshot(path : String) = "mbg_screenshot"

///|
/// A scene node the engine owns and an agent would manipulate.
struct Node {
  kind : Int // 0 rect, 1 circle, 2 text, 3 line
  x : Double
  y : Double
  w : Double
  h : Double
  radius : Double
  color : (Int, Int, Int)
  label : String
  // animation
  orbit_center : (Double, Double)
  orbit_radius : Double
  orbit_speed : Double
  orbit_phase : Double
  spin : Double
}

///|
fn Node::rect(
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  radius : Double,
  color : (Int, Int, Int)
) -> Node {
  {
    kind: 0,
    x,
    y,
    w,
    h,
    radius,
    color,
    label: "",
    orbit_center: (0.0, 0.0),
    orbit_radius: 0.0,
    orbit_speed: 0.0,
    orbit_phase: 0.0,
    spin: 0.0,
  }
}

///|
fn Node::circle(
  x : Double,
  y : Double,
  radius : Double,
  color : (Int, Int, Int)
) -> Node {
  {
    kind: 1,
    x,
    y,
    w: radius,
    h: radius,
    radius,
    color,
    label: "",
    orbit_center: (0.0, 0.0),
    orbit_radius: 0.0,
    orbit_speed: 0.0,
    orbit_phase: 0.0,
    spin: 0.0,
  }
}

///|
fn Node::text(
  x : Double,
  y : Double,
  size : Double,
  color : (Int, Int, Int),
  label : String
) -> Node {
  {
    kind: 2,
    x,
    y,
    w: size,
    h: size,
    radius: 0.0,
    color,
    label,
    orbit_center: (0.0, 0.0),
    orbit_radius: 0.0,
    orbit_speed: 0.0,
    orbit_phase: 0.0,
    spin: 0.0,
  }
}

///|
fn Node::with_orbit(
  self : Node,
  cx : Double,
  cy : Double,
  radius : Double,
  speed : Double,
  phase : Double
) -> Node {
  {
    ..self,
    orbit_center: (cx, cy),
    orbit_radius: radius,
    orbit_speed: speed,
    orbit_phase: phase,
  }
}

///|
/// Resolve a node's position at time t. Orbiting nodes compute their own
/// position; everything else sits where it was declared.
fn Node::position_at(self : Node, t : Double) -> (Double, Double) {
  if self.orbit_radius > 0.0 {
    let ang = self.orbit_phase + t * self.orbit_speed * 3.141592653589793 / 180.0
    let (cx, cy) = self.orbit_center
    (cx + @math.cos(ang) * self.orbit_radius, cy + @math.sin(ang) * self.orbit_radius)
  } else {
    (self.x, self.y)
  }
}

///|
fn Node::draw(self : Node, t : Double) -> Unit {
  let (x, y) = self.position_at(t)
  let (r, g, b) = self.color
  match self.kind {
    0 =>
      mbg_rect(x, y, self.w, self.h, self.radius, r, g, b)
    1 => mbg_circle(x, y, self.w, r, g, b)
    2 => {
      let _ = mbg_text(self.label, x, y, self.w, r, g, b)
    }
    _ => mbg_line(x, y, self.w, self.h, 2.0, r, g, b)
  }
}

///|
fn build_scene() -> Array[Node] {
  let nodes : Array[Node] = []
  // hero card
  nodes.push(Node::rect(72.0, 96.0, 460.0, 236.0, 28.0, (25, 30, 44)))
  nodes.push(Node::rect(72.0, 96.0, 6.0, 236.0, 3.0, (229, 72, 77)))
  nodes.push(
    Node::text(112.0, 136.0, 40.0, (238, 241, 247), "MoonBit drives the engine"),
  )
  nodes.push(
    Node::text(112.0, 194.0, 19.0, (139, 147, 167), "scene logic + timing in MoonBit"),
  )
  nodes.push(
    Node::text(112.0, 236.0, 16.0, (89, 96, 122), "raylib only draws"),
  )
  // orbiters
  nodes.push(Node::circle(0.0, 0.0, 10.0, (245, 165, 36)).with_orbit(880.0, 300.0, 0.0, 0.0, 0.0))
  nodes.push(Node::circle(0.0, 0.0, 8.0, (48, 164, 108)).with_orbit(880.0, 300.0, 150.0, 60.0, 0.0))
  nodes.push(Node::circle(0.0, 0.0, 6.0, (229, 72, 77)).with_orbit(880.0, 300.0, 200.0, -45.0, 1.6))
  nodes.push(Node::circle(0.0, 0.0, 11.0, (124, 102, 220)).with_orbit(880.0, 300.0, 250.0, 28.0, 2.4))
  nodes.push(Node::rect(72.0, 560.0, 1136.0, 2.0, 0.0, (35, 42, 61)))
  nodes.push(
    Node::text(72.0, 590.0, 17.0, (74, 81, 99), "keys: S shot  space pause  esc quit"),
  )
  nodes
}

///|
fn parse_int(s : String) -> Int {
  let mut n = 0
  for c in s {
    let d = c.to_int() - 48
    if d >= 0 && d <= 9 {
      n = n * 10 + d
    }
  }
  n
}

///|
fn draw_frame(scene : Array[Node], frame : Int, t : Double) -> Unit {
  mbg_clear(11, 13, 19)
  for node in scene {
    node.draw(t)
  }
  let _ = mbg_text(
    "MoonBit + raylib  |  frame \{frame}  |  fps \{mbg_fps()}",
    12.0,
    10.0,
    19.0,
    200,
    208,
    224,
  )
}

///|
fn main {
  // Minimal argv handling: --shot <path> and --frames <n> keep the probe scriptable
  let argv = @env.args()
  let mut shot : String = ""
  let mut shot_frame : Int = 90
  let mut i = 1
  while i < argv.length() {
    let a = argv[i]
    if a == "--shot" && i + 1 < argv.length() {
      shot = argv[i + 1]
      i = i + 2
    } else if a == "--frames" && i + 1 < argv.length() {
      shot_frame = parse_int(argv[i + 1])
      i = i + 2
    } else {
      i = i + 1
    }
  }

  mbg_init("deepEngine spike — MoonBit + raylib")
  let scene = build_scene()

  let mut frame = 0
  let mut paused = false
  while mbg_should_close() == 0 {
    if mbg_key_pressed(32) != 0 { // KEY_SPACE
      paused = !paused
    }
    if mbg_key_pressed(256) != 0 { // KEY_ESCAPE
      break
    }

    let t = frame.to_double() / 60.0

    mbg_begin_frame()
    draw_frame(scene, frame, t)
    // Capture reads the framebuffer, so the pending batch must be flushed while
    // the frame is still open
    if shot != "" && frame >= shot_frame {
      mbg_screenshot(shot)
    }
    mbg_end_frame()

    if shot != "" && frame >= shot_frame {
      break
    }

    if !paused {
      frame = frame + 1
    }
  }

  mbg_close()
}
