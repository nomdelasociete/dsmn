// The shader dithers the actual laptop raster. Motion changes the light very
// slightly, leaving the silhouette and pixel grid stable.
export function mountDither({ motionPaused }) {
  const image = document.querySelector('#mac-source');
  const canvas = document.querySelector('#mac-dither');
  const stage = document.querySelector('#demo');
  if (!image || !canvas || !stage) return;
  const gl = canvas.getContext('webgl', { alpha: false, antialias: false, powerPreference: 'low-power', preserveDrawingBuffer: true });
  if (!gl) return;
  const vertex = `
    attribute vec2 position;
    varying vec2 uv;
    void main() {
      uv = position * 0.5 + 0.5;
      gl_Position = vec4(position, 0.0, 1.0);
    }`;
  const fragment = `
    precision mediump float;
    uniform sampler2D artwork;
    uniform float pixelScale;
    uniform float time;
    uniform float moving;
    uniform float pointer;
    varying vec2 uv;
    float bayer(vec2 pixel) {
      vec2 p = mod(pixel, 4.0);
      float i = p.x + p.y * 4.0;
      if(i < 0.5) return 0.0;
      if(i < 1.5) return 8.0;
      if(i < 2.5) return 2.0;
      if(i < 3.5) return 10.0;
      if(i < 4.5) return 12.0;
      if(i < 5.5) return 4.0;
      if(i < 6.5) return 14.0;
      if(i < 7.5) return 6.0;
      if(i < 8.5) return 3.0;
      if(i < 9.5) return 11.0;
      if(i < 10.5) return 1.0;
      if(i < 11.5) return 9.0;
      if(i < 12.5) return 15.0;
      if(i < 13.5) return 7.0;
      if(i < 14.5) return 13.0;
      return 5.0;
    }
    void main() {
      vec3 source = texture2D(artwork, uv).rgb;
      float luma = dot(source, vec3(0.299, 0.587, 0.114));
      // Lift the generated image's pale background into the exact page color.
      float brightness = luma > 0.915 ? 1.0 : pow(luma, 0.9);
      float light = sin(uv.x * 8.0 - time * 0.55) * 0.017 * moving;
      light += exp(-pow((uv.x - pointer) * 5.0, 2.0)) * 0.025 * moving;
      float threshold = (bayer(floor(gl_FragCoord.xy / pixelScale)) + 0.5) / 16.0;
      float dotValue = step(threshold, min(1.0, brightness + light));
      vec3 paper = vec3(241.0, 240.0, 231.0) / 255.0;
      vec3 ink = vec3(37.0, 41.0, 34.0) / 255.0;
      gl_FragColor = vec4(mix(ink, paper, dotValue), 1.0);
    }`;
  function compile(type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      gl.deleteShader(shader);
      return null;
    }
    return shader;
  }
  const vs = compile(gl.VERTEX_SHADER, vertex);
  const fs = compile(gl.FRAGMENT_SHADER, fragment);
  if (!vs || !fs) return;
  const program = gl.createProgram();
  gl.attachShader(program, vs);
  gl.attachShader(program, fs);
  gl.linkProgram(program);
  gl.deleteShader(vs);
  gl.deleteShader(fs);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) return;
  gl.useProgram(program);
  const buffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1,1,-1,-1,1,-1,1,1,-1,1,1]), gl.STATIC_DRAW);
  const position = gl.getAttribLocation(program, 'position');
  gl.enableVertexAttribArray(position);
  gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);
  const texture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
  const uniforms = Object.fromEntries(['artwork', 'pixelScale', 'time', 'moving', 'pointer'].map(name => [name, gl.getUniformLocation(program, name)]));
  gl.uniform1i(uniforms.artwork, 0);
  let ready = false;
  let inView = true;
  let frame = 0;
  let lastFrame = 0;
  let elapsed = 0;
  let pointer = -1;
  let lost = false;
  function running() { return ready && !lost && !document.hidden && inView && !motionPaused() && stage.dataset.active === 'true'; }
  function resize() {
    const box = canvas.getBoundingClientRect();
    const scale = Math.min(window.devicePixelRatio || 1, 2);
    const width = Math.max(1, Math.round(box.width * scale));
    const height = Math.max(1, Math.round(box.height * scale));
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
      gl.viewport(0, 0, width, height);
    }
  }
  function draw() {
    if (!ready || lost) return;
    resize();
    gl.uniform1f(uniforms.pixelScale, Math.min(window.devicePixelRatio || 1, 2));
    gl.uniform1f(uniforms.time, elapsed);
    gl.uniform1f(uniforms.moving, running() ? 1 : 0);
    gl.uniform1f(uniforms.pointer, pointer);
    gl.drawArrays(gl.TRIANGLES, 0, 6);
  }
  function animate(now) {
    if (!running()) { frame = 0; return; }
    // This quiet animation only needs 24 fps.
    if (now - lastFrame >= 1000 / 24) {
      elapsed += Math.min((now - lastFrame) / 1000, 0.1);
      lastFrame = now;
      draw();
    }
    frame = requestAnimationFrame(animate);
  }
  function sync() {
    cancelAnimationFrame(frame);
    frame = 0;
    draw();
    if (running()) {
      lastFrame = performance.now();
      frame = requestAnimationFrame(animate);
    }
  }
  function upload() {
    if (ready || !image.naturalWidth) return;
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, gl.RGB, gl.UNSIGNED_BYTE, image);
    ready = true;
    image.parentElement.classList.add('is-ready');
    sync();
  }
  image.addEventListener('load', upload, { once: true });
  if (image.complete) upload();
  new ResizeObserver(sync).observe(canvas);
  new IntersectionObserver(([entry]) => { inView = entry.isIntersecting; sync(); }).observe(canvas);
  document.addEventListener('visibilitychange', sync);
  document.addEventListener('dsmn:motion', sync);
  document.addEventListener('dsmn:activity', sync);
  canvas.addEventListener('pointermove', (event) => {
    const box = canvas.getBoundingClientRect();
    pointer = (event.clientX - box.left) / box.width;
  }, { passive: true });
  canvas.addEventListener('pointerleave', () => { pointer = -1; });
  canvas.addEventListener('webglcontextlost', () => {
    lost = true;
    cancelAnimationFrame(frame);
    image.parentElement.classList.remove('is-ready');
    canvas.hidden = true;
  });
}
