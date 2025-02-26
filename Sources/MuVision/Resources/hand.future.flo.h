// future fixes for  MuFlo
hand.{ left right }.{
    thumb  {      knuc base inter tip }
    index  { meta knuc base inter tip }
    middle { meta knuc base inter tip }
    ring   { meta knuc base inter tip }
    little { meta knuc base inter tip }
    wrist
    forearm
    canvas << middle.tip // last item ignores edge?
}
// decorate leaves with expressions, while keeping edges intact
hand˚.(x -0.3…0.3, y 0.8…1.2, z -0.5…0.01, time, phase, joint)
// not yet working?
