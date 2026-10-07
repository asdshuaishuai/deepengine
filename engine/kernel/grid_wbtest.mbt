// grid 内核白盒测试

///|
// 地图（cols=10, rows=5）：
// row0: 全墙
// row1: 地板
// row2: p(2) b(5) g(8)
// row3: 地板
// row4: 全墙
fn make_grid() -> GridGame {
  let walls : Array[(Int, Int)] = []
  let mut x = 0
  while x < 10 {
    walls.push((x, 0))
    walls.push((x, 4))
    x = x + 1
  }
  walls.push((0, 1))
  walls.push((0, 2))
  walls.push((0, 3))
  walls.push((9, 1))
  walls.push((9, 2))
  walls.push((9, 3))
  let boxes : Array[(Int, Int)] = [(5, 2)]
  let goals : Array[(Int, Int)] = [(8, 2)]
  GridGame::new(10, 5, 0, 2, 2, walls, boxes, goals)
}

///|
test "grid：四向移动与墙阻挡" {
  let g = make_grid()
  let g2 = grid_run_script(g, "right:1")
  assert_true(g2.px == 3 && g2.moves == 1)
  let g3 = grid_run_script(g, "up:5")
  assert_true(g3.py == 1) // 顶到 row0 墙
  assert_true(g3.moves == 1) // 只成功一次
}

///|
test "grid：推箱与受阻" {
  let g = make_grid()
  // 绕到箱子左侧再推
  let g2 = grid_run_script(g, "left:1, up:1, right:3, down:1, right:1")
  // left:1 → (1,2)；up:1 → (1,1)；right:3 → (4,1)；down:1 → (4,2)；right:1 → 推箱 (5,2)→(6,2)
  assert_true(g2.px == 5)
  match box_idx(g2, 6, 2) {
    true => ()
    false => fail("箱子应被推到 (6,2)")
  }
  // 箱子未到目标
  assert_true(g2.state == "playing")
  assert_true(grid_boxes_on(g2) == 0)
}

///|
fn box_idx(g : GridGame, x : Int, y : Int) -> Bool {
  for b in g.boxes {
    let (bx, by) = b
    if bx == x && by == y {
      return true
    }
  }
  false
}

///|
test "grid：推到目标 = won" {
  let g = make_grid()
  let g2 = grid_run_script(g, "left:1, up:1, right:3, down:1, right:3")
  // 推箱 (5,2)→(6,2)→(7,2)→(8,2)，玩家到 (7,2)
  assert_true(g2.state == "won")
  assert_true(grid_boxes_on(g2) == 1)
}

///|
test "grid：箱子抵墙推不动" {
  // 箱子在墙边（x=8 邻右侧 x=9 是墙）？构造：箱子 (8,2) 目标 (3,2)
  let walls : Array[(Int, Int)] = []
  let mut x = 0
  while x < 10 {
    walls.push((x, 0))
    walls.push((x, 4))
    x = x + 1
  }
  walls.push((0, 1))
  walls.push((0, 2))
  walls.push((0, 3))
  walls.push((9, 1))
  walls.push((9, 2))
  walls.push((9, 3))
  let boxes : Array[(Int, Int)] = [(8, 2)]
  let goals : Array[(Int, Int)] = [(3, 2)]
  let g = GridGame::new(10, 5, 0, 6, 2, walls, boxes, goals)
  // 从左侧推：right:2 → 第一次到 (7,2)，第二次推箱 (8,2)→(9,2)=墙 → 阻塞
  let g2 = grid_run_script(g, "right:2")
  assert_true(g2.px == 7)
  assert_true(box_idx(g2, 8, 2)) // 箱子没动
  assert_true(g2.moves == 1)
}

///|
test "grid：verify 全链（通用 + 声明）" {
  let g = make_grid()
  let probes : Array[Probe] = [
    { name: "push_win", script: "left:1, up:1, right:3, down:1, right:3", expect: "state==won" },
    { name: "moves_counted", script: "right:1", expect: "moves==1" },
  ]
  let r = verify_grid(g, probes)
  assert_true(r.total == 6)
  assert_true(r.reward == 1)
}

///|
test "grid：确定性双跑一致" {
  let g = make_grid()
  let a = grid_serialize(grid_run_script(g, "up:2, right:3, down:1"))
  let b = grid_serialize(grid_run_script(g, "up:2, right:3, down:1"))
  assert_true(a == b)
}

///|
test "衍生：grid 运行时生成箱子并可推" {
  let g = make_grid()
  // 玩家 (2,2) 右侧 (3,2) 现场生成箱子
  assert_true(grid_spawn_box(g, 3, 2) == true)
  let g2 = grid_run_script(g, "right:2")
  // 推箱：(3,2)→(4,2)，玩家到 (3,2)
  assert_true(g2.px == 3)
  assert_true(box_idx(g2, 4, 2))
}

///|
test "衍生：grid spawn 占用格拒绝" {
  let g = make_grid()
  assert_true(grid_spawn_box(g, 3, 4) == false) // 已有箱
  assert_true(grid_spawn_wall(g, 2, 2) == false) // 玩家所在
  assert_true(grid_spawn_box(g, -1, 0) == false) // 越界
}

///|
test "衍生：生成即就位的目标直接判胜" {
  let g = make_grid()
  let g2 = GridGame::clone(g)
  // 箱 (5,2)；生成一个目标在 (5,2) → 立即 won
  assert_true(grid_spawn_goal(g2, 5, 2) == true)
  assert_true(g2.state == "won")
}
