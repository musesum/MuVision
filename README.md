## MuMetal /micro metal/

MuMetal manages an Apple Metal pipeline via a `.flo.h` script. For a working example, see the DeepMuse `pipe.flo.h` script file. 

#### Here is a simple pipeline 
```c
pipe (on 1) {
    
    draw (on 1) { // shader
        in (tex) // texture
        out (tex) // texture
    }
    render (on 1) { // shader
        in (tex, <- draw.out)
    }
} 
```
##### breakdown of each line

`pipe` is the root of the pipeline tree
`pipe (on 1) {...}` on 1 means that everything under pipe is active
`draw (on 1) {...}` is a compute shader which two textures `in` and `out`
`in (tex)` is a texture that is declared and bound in swift code
`out (tex)` is another texture declared and bound in swift
`render (on 1) {...}` is render shader 
`in (tex) << draw.out` accepts `draw.out` and is shared as a reference 

##### details 

 `(on 1)` means to flow through that part of the pipeline
 `(on 0)` means skip that part of the pipeline
 `in (tex) << draw.out` copies a reference to draw.out's MTLTexture

### super and sub pipes 

In the pipe hierarchy, you can treat buffers and textures like sub-classed members. 

For example, let's start with an explictly declared `in(tex)`, which is shared by `flat`, `cube`, and `plato`: 

```c
    render (on 1) {
        map (on 1)  {
            flat(on 1) {
                in (tex, <- draw.out)
            }
            cube(on 0) {
                in (tex, <- draw.out)
            } 
        }
        plato (on 1) {
            in (tex, <- tile.out)
        }
    }
```
and in swift code, bind to `in(tex)` like so: 

```
inTex˚ = pipeNode˚.bind("flat.in") // in FlatNode.swift

inTex˚ = pipeNode˚.bind("cube.in") // in CubeNode.swift

inTex˚ = pipeNode˚.bind("plato.in") // in PlatoNode.swift
```

Because `in(tex)` is shared by `flat`, `cube`, and `plato`, we can instead declare it under `render` like so: 

```c
    render (on 1) {
        
        in (tex, <- draw.out)

        map (on 1)  {
            flat(on 1)
            cube(on 0) 
        }
        plato (on 1) 
    }
```
and replace the swift bindings like so: 

```
inTex˚ = pipeNode˚.superBind("in") // in FlatNode.swift
...
inTex˚ = pipeNode˚.superBind("in") // in CubeNode.swift
...
inTex˚ = pipeNode˚.superBind("in")  // in PlatoNode.swift
```

this is a bit more concise. 


### Pipes, Textures, and Buffers
```
flat (on 1) // is pipe, that discovered by a shader
in (tex) // is a MTLTexture that can be shared between shaders
repeat (buf, x -1…1~0, y -1…1~0) // is a MTLBuffer, with x,y values
```

### Backlog: scripted runtime shaders

The goal is to allow a naive user to wire together shaders and renders with minimal details about buffer and texture numbers. 

Not quite there yet. In a previous version, user could embed a Metal shader into the script and compile during runtime. On the backlog.
