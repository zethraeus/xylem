class Camera
	constructor: () ->
		@modelMatrix = mat4.create()
		@viewMatrix = mat4.create()
		@projectionMatrix = mat4.create()
		this.resetModelMatrix()

	translate: (vector)->
		mat4.translate(@modelMatrix, vector)
	
	rotate: (degrees, axis)->
		mat4.rotate(@modelMatrix, degToRad(degrees), axis)
	
	setProperties: (fov, viewportWidth, viewportHeight, nearClip, farClip)->
		mat4.perspective(fov, viewportWidth / viewportHeight, nearClip, farClip, @projectionMatrix)
	
	getModelMatrix: ()->
		return @modelMatrix

	getProjectionMatrix: ()->
		return @projectionMatrix

	getViewMatrix: ()->
		this.recalculateViewMatrix()
		return @viewMatrix

	resetModelMatrix: ()->
		mat4.identity(@modelMatrix)

	recalculateViewMatrix: ()->
		mat4.inverse(@modelMatrix, @viewMatrix)