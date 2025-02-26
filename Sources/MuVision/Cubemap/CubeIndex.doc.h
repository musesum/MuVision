


left+90 ║  top  ║ right-90
════════╝       ╚══════════════
left      front   right    back
════════╗       ╔══════════════
left-90 ║  bot  ║ right+90

here is a mapping of a 6x6 indices as faces (Quad) on a cube
numbers shorten (x,y) as xy. For example, (1,2) as 12

55 54 53 52 51 50 ║ 50 40 30 20 10 00 ║ 00 01 02 03 04 05
45 44 43 42 41 40 ║ 40 41 31 21 11 10 ║ 10 11 12 13 14 15
35 34 33 32 31 30 ║ 30 31 32 22 21 20 ║ 20 21 22 23 24 25
25 24 23 22 21 20 ║ 20 21 22 32 31 30 ║ 30 31 32 33 34 35
15 14 13 12 11 10 ║ 10 11 21 31 41 40 ║ 40 41 42 43 44 45
05 04 03 02 01 00 ║ 00 10 20 30 40 50 ║ 50 51 52 53 54 55
══════════════════╝                   ╚══════════════════════════════════════
50 40 30 20 10 00   00 10 20 30 40 50   50 40 30 20 10 00   00 10 20 30 40 50
51 41 31 21 11 01   01 11 21 31 41 51   51 41 31 21 11 01   01 11 21 31 41 51
52 42 32 22 12 02   02 12 22 32 42 52   52 42 32 22 12 02   02 12 22 32 42 52
53 43 33 23 13 03   03 13 23 33 43 53   53 43 33 23 13 03   03 13 23 33 43 53
54 44 34 24 14 04   04 14 24 34 44 54   54 44 34 24 14 04   04 14 24 34 44 54
55 45 35 25 15 05   05 15 25 35 45 55   55 45 35 25 15 05   05 15 25 35 45 55
══════════════════╗                   ╔══════════════════════════════════════
00 01 02 03 04 05 ║ 05 15 25 35 45 55 ║ 55 54 53 52 51 50
10 11 12 13 14 15 ║ 15 14 24 34 44 45 ║ 45 44 43 42 41 40
20 21 22 23 24 25 ║ 25 24 23 33 34 35 ║ 35 34 33 32 31 30
30 31 32 33 34 35 ║ 35 34 33 23 24 25 ║ 25 24 23 22 21 20
40 41 42 43 44 45 ║ 45 44 34 24 14 15 ║ 15 14 13 12 11 10
50 51 52 53 54 55 ║ 55 45 35 25 15 05 ║ 05 04 03 02 01 00

there are for corners and a center

nw - north west
ne - north west
se - south east
sw - south west
c  - center

Each face (Quad) consists for 4 triangles (Tri) proceeding from each corner
for example: nw_ne_c goes from  northWest to northEast to center, clockwise

here are the 8 Tri sets, running clockwise and counterClockwise
// clockwise    counter
    nw_ne_c     ne_nw_c
    ne_se_c     se_ne_c
    se_sw_c     sw_se_c
    sw_nw_c     nw_sw_c

The front Quad


Constructing the 6 quads is a matter of mapping Tris from the front face,
which has indices that match the position of the corresponding 2D texture

Mapping the sides are easy, simple mirror the front face's indices --
both the Left and Right Quads are mirrored hoizontally, while the
Back Quad is a duplicate of the Front Quad. No Tri are needed, here.

Mapping the Top and Bot (bottom) Quads is where the Tris come into play:
The Top Quad maps the Front Quad's top Tri 4 times, flipped and mirrored.
The Bot Quad maps the Front Quad's bottom Tri 4 times, in the same way.

To map Tris, makeCubeTris() creates an array of indices point to the Front.
So the front indices for Front's top Tri:

Front (.nw_ne_c)
00 10 20 30 40 50
   11 21 31 41
      22 32

will map to Top Quad's like so

Top (.ne_nw_c)
50 40 30 20 10 00
   41 21 31 11
      32 22

The two arrays are then processed for the transformation

mapped from (.nw_ne_c) to (.ne_nw_c)
address:    00 01 02 03 04 05 07 08 09 10 14 15
front:      00 10 20 30 40 50 11 21 31 41 22 32
top:        50 40 30 20 10 00 41 21 31 11 32 22

Here is the log of each step for makeTop()

mapTris(.ne_nw_c, to: .nw_ne_c, &top) ; logQuad(top)

src: 50 40 30 20 10 00 41 31 21 11 32 22
dst: 00 10 20 30 40 50 11 21 31 41 22 32

50 40 30 20 10 00
-- 41 31 21 11 --
-- -- 32 22 -- --
-- -- -- -- -- --
-- -- -- -- -- --
-- -- -- -- -- --

mapTris(.nw_ne_c, to: .ne_se_c, &top) ; logQuad(top)

src: 00 10 20 30 40 50 11 21 31 41 22 32
dst: 50 51 52 53 54 55 41 42 43 44 32 33

50 40 30 20 10 00
-- 41 31 21 11 10
-- -- 32 22 21 20
-- -- -- 32 31 30
-- -- -- -- 41 40
-- -- -- -- -- 50

mapTris(.ne_nw_c, to: .se_sw_c, &top) ; logQuad(top)

src: 50 40 30 20 10 00 41 31 21 11 32 22
dst: 55 45 35 25 15 05 44 34 24 14 33 23

50 40 30 20 10 00
-- 41 31 21 11 10
-- -- 32 22 21 20
-- -- 22 32 31 30
-- 11 21 31 41 40
00 10 20 30 40 50

mapTris(.nw_ne_c, to: .sw_nw_c, &top) ; logQuad(top)

src: 00 10 20 30 40 50 11 21 31 41 22 32
dst: 05 04 03 02 01 00 14 13 12 11 23 22

50 40 30 20 10 00
40 41 31 21 11 10
30 31 32 22 21 20
20 21 22 32 31 30
10 11 21 31 41 40
00 10 20 30 40 50 
