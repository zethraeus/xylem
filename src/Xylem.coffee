class Xylem

    constructor: (canvas)->
        @gl = null
        @sceneGraph = null
        @gl = @initializeGL(canvas)
        @gBuffer = new GBuffer(@gl, [nextHighestPowerOfTwo(canvas.width), nextHighestPowerOfTwo(canvas.height)])
        @buffers = [new Texture(@gl, [nextHighestPowerOfTwo(canvas.width), nextHighestPowerOfTwo(canvas.height)])
                    new Texture(@gl, [nextHighestPowerOfTwo(canvas.width), nextHighestPowerOfTwo(canvas.height)])]
        @currBuffer = 0
        @screenQuad = new FullscreenQuad(@gl)

    initializeGL: (canvas)->
        gl = canvas.getContext("webgl") || canvas.getContext("experimental-webgl")
        gl.viewportWidth = canvas.width
        gl.viewportHeight = canvas.height
        gl.enable(gl.CULL_FACE)
        gl.cullFace(gl.BACK)
        gl.clearColor(0.0, 0.0, 0.0, 1.0)
        gl.disable(gl.BLEND)
        gl.enable(gl.DEPTH_TEST)
        gl.depthFunc(gl.LEQUAL)
        gl.getExtension('OES_texture_float')
        gl.viewport(0, 0, gl.viewportWidth, gl.viewportHeight)
        if not gl
            throw "Could not initialize WebGL."
        else
            return gl

    loadScene: (scene, callback)->
        @loadSceneResources(
            scene,
            (map, success)=>
                @setUpScene(scene, map, success, callback)
        )

    loadSceneResources: (scene, callback)->
        rl = new ResourceLoader()
        rl.load(
            scene.resources,
            callback
        )

    setUpScene: (scene, @resourceMap, loadSuccessful, callback)->
        if not loadSuccessful
            throw "Not all necessary resources could be loaded."
        @sceneGraph = new SceneGraph()

        objTraverse = (parentNode, obj)=>
            type = getOrThrow(obj, "type")
            node = null
            if type is "object"
                node = new SceneObject()
                model = new Model(@gl)
                model.loadModel(@resourceMap[getOrThrow(obj, "model")])
                node.setModel(model)
                if obj.texture?
                    node.setTexture(new Texture.fromImage(@gl, @resourceMap[obj.texture]))
                if obj.scale?
                    node.scale(obj.scale)
            else if type is "light"
                node = new SceneLight()
                node.setAmbientColor(getOrThrow(obj, "ambientColor"))
                node.setDiffuseColor(getOrThrow(obj, "diffuseColor"))
                node.setSpecularColor(getOrThrow(obj, "specularColor"))
                node.setSpecularHardness(getOrThrow(obj, "specularHardness"))
            else if type is "camera"
                node = new SceneCamera()
                node.setProperties(
                    degreesToRadians(getOrThrow(obj, "fieldOfViewAngle")),
                    @gl.viewportWidth,
                    @gl.viewportHeight,
                    getOrThrow(obj, "nearPlaneDistance"),
                    getOrThrow(obj, "farPlaneDistance")
                )
            else
                throw "A node of an unsupported or unmarked type was found."
            parentNode.addChild(node)
            if obj.translate?
                node.translate(obj.translate)
            if obj.rotation?
                node.rotate(degreesToRadians(getOrThrow(obj.rotation, "degrees")), getOrThrow(obj.rotation, "axis"))
            if obj.children?
                for childObj in obj.children
                    objTraverse(node, childObj)
        
        @sceneGraph.setRoot(new SceneNode())
        objs = getOrThrow(scene, "tree")
        for obj in objs
            objTraverse(@sceneGraph.getRoot(), obj)

        callback()
    
    draw: ()->
        #consider drawing to same layer w/ additive blend mode?
        @gBuffer.populate((x)=>@sceneGraph.draw(x))
        @gBuffer.normalsTexture.bind(0)
        @gBuffer.albedoTexture.bind(1)
        @gBuffer.positionTexture.bind(2)
        light = @sceneGraph.getNodesOfType(SceneLight)[0]
        @combineProgram = new ShaderProgram(@gl)
        @combineProgram.compileShader(
            "
                precision mediump float;
                varying vec2 vTextureCoord;
                uniform sampler2D normals;
                uniform sampler2D albedos;
                uniform sampler2D positions;
                uniform vec3 ambientColor;
                uniform vec3 pointLightingLocation;
                uniform vec3 pointLightingSpecularColor;
                uniform vec3 pointLightingDiffuseColor;
                uniform float specularHardness;
                void main(void) {
                    vec4 normal = texture2D(normals, vTextureCoord);
                    vec4 albedo = texture2D(albedos, vTextureCoord);
                    vec4 position = texture2D(positions, vTextureCoord);
                    vec3 lightDirection = normalize(pointLightingLocation - position.xyz);
                    vec3 eyeDirection = normalize(-position.xyz);
                    vec3 reflectionDirection = reflect(-lightDirection, normal.xyz);
                    float specularLightWeighting = pow(max(dot(reflectionDirection, eyeDirection), 0.0), specularHardness);
                    float diffuseLightWeighting = max(dot(normal.xyz, lightDirection), 0.0);
                    vec3 lightWeighting = ambientColor
                        + pointLightingSpecularColor * specularLightWeighting
                        + pointLightingDiffuseColor * diffuseLightWeighting;

                    gl_FragColor = vec4(albedo.rgb * lightWeighting, albedo.a);
                }
            "
            @gl.FRAGMENT_SHADER
        )
        @combineProgram.compileShader(
            "
                attribute vec3 vertexPosition;
                attribute vec2 textureCoord;
                varying vec2 vTextureCoord;
                void main(void) {
                    gl_Position = vec4(vertexPosition, 1.0);
                    vTextureCoord = textureCoord;
                }
            "
            @gl.VERTEX_SHADER
        )
        @combineProgram.linkProgram()
        @combineProgram.enableProgram()
        light.setUniforms(@combineProgram, [0,3,3])
        @combineProgram.enableAttribute("vertexPosition")
        @combineProgram.enableAttribute("textureCoord")
        @combineProgram.setUniform1i("normals", 0)
        @combineProgram.setUniform1i("albedos", 1)
        @combineProgram.setUniform1i("positions", 2)
        @buffers[@currBuffer].drawTo(
            ()=>
                @gl.clear(@gl.COLOR_BUFFER_BIT)
                @screenQuad.draw(@combineProgram)
            false
        )
        @combineProgram.disableAttribute("vertexPosition")
        @combineProgram.disableAttribute("textureCoord")


        @screenQuad.drawWithTexture(@buffers[@currBuffer])


    mainLoop: ()->
        @draw()
        browserVersionOf("requestAnimationFrame")(()=>@mainLoop())

window.Xylem = Xylem
