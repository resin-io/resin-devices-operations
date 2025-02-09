m = require('mochainon')
Promise = require('bluebird')
fs = Promise.promisifyAll(require('fs'))
path = require('path')
imagefs = require('balena-image-fs')
wary = require('wary')
rindle = require('rindle')
operations = require('../lib/operations')
utils = require('../lib/utils')
sdk = require('etcher-sdk')

RASPBERRY_PI = path.join(__dirname, 'images', 'raspberrypi.img')
EDISON = path.join(__dirname, 'images', 'edison-config.img')
EDISON_ZIP = path.join(__dirname, 'images', 'edison')
RANDOM = path.join(__dirname, 'images', 'device.random')

FILES =
	'cmdline.txt': 'dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait \n'

extract = (streamDisposer) ->
	return Promise.using streamDisposer, (stream) ->
		return new Promise (resolve, reject) ->
			result = ''
			stream.on('error', reject)
			stream.on 'data', (chunk) ->
				result += chunk
			stream.on 'end', ->
				resolve(result)

wary.it 'should be fulfilled if no operations', {}, ->
	configuration = operations.execute(RASPBERRY_PI, [])
	promise = rindle.wait(configuration)
	m.chai.expect(promise).to.be.fulfilled

wary.it 'should be fulfilled if operations is undefined', {}, ->
	configuration = operations.execute(RASPBERRY_PI)
	promise = rindle.wait(configuration)
	m.chai.expect(promise).to.be.fulfilled

wary.it 'should be fulfilled even if it finished long ago', {}, ->
	f = ->
		configuration = operations.execute(RASPBERRY_PI)
		Promise.delay(1000).return(configuration)

	f().then (configuration) ->
		promise = rindle.wait(configuration)
		m.chai.expect(promise).to.be.fulfilled

wary.it 'should be rejected if the command does not exist',
	raspberrypi: RASPBERRY_PI
, (images) ->
	configuration = operations.execute images.raspberrypi, [
		command: 'foobar'
	]

	promise = rindle.wait(configuration)
	m.chai.expect(promise).to.be.rejectedWith('Unknown command: foobar')

wary.it 'should be able to copy a single file between raspberry pi partitions',
	raspberrypi: RASPBERRY_PI
, (images) ->
	configuration = operations.execute images.raspberrypi, [
		command: 'copy'
		from:
			partition:
				primary: 1
			path: '/cmdline.txt'
		to:
			partition:
				primary: 4
				logical: 1
			path: '/cmdline.txt'
	]

	rindle.wait(configuration).then ->
		imagefs.interact(
			images.raspberrypi
			5
			(_fs) ->
				readFileAsync = Promise.promisify(_fs.readFile)
				return readFileAsync('/cmdline.txt')
					.then (b) ->
						return b.toString()
		)
	.then (contents) ->
		m.chai.expect(contents).to.equal(FILES['cmdline.txt'])

wary.it 'should copy multiple files between raspberry pi partitions',
	raspberrypi: RASPBERRY_PI
, (images) ->
	configuration = operations.execute images.raspberrypi, [
		command: 'copy'
		from:
			partition:
				primary: 1
			path: '/cmdline.txt'
		to:
			partition:
				primary: 4
				logical: 1
			path: '/cmdline.txt'
	,
		command: 'copy'
		from:
			partition:
				primary: 4
				logical: 1
			path: '/cmdline.txt'
		to:
			partition:
				primary: 1
			path: '/cmdline.copy'
	]

	rindle.wait(configuration).then ->
		imagefs.interact(
			images.raspberrypi
			1
			(_fs) ->
				readFileAsync = Promise.promisify(_fs.readFile)
				return readFileAsync('/cmdline.copy')
					.then (b) -> 
						return b.toString()
		)
	.then (contents) ->
		m.chai.expect(contents).to.equal(FILES['cmdline.txt'])

wary.it 'should be able to replace a single file from a raspberry pi partition',
	raspberrypi: RASPBERRY_PI
, (images) ->
	configuration = operations.execute images.raspberrypi, [
		command: 'replace'
		file:
			partition:
				primary: 1
			path: '/cmdline.txt'
		find: 'lpm_enable=0'
		replace: 'lpm_enable=1'
	]

	rindle.wait(configuration).then ->
		imagefs.interact(
			images.raspberrypi
			1
			(_fs) ->
				readFileAsync = Promise.promisify(_fs.readFile)
				return readFileAsync('/cmdline.txt')
					.then (b) -> 
						return b.toString()
		)
	.then (contents) ->
		m.chai.expect(contents).to.equal('dwc_otg.lpm_enable=1 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait \n')

wary.it 'should be able to perform multiple replaces in an raspberry pi partition',
	raspberrypi: RASPBERRY_PI
, (images) ->
	configuration = operations.execute images.raspberrypi, [
		command: 'replace'
		file:
			partition: 1
			path: '/cmdline.txt'
		find: 'lpm_enable=0'
		replace: 'lpm_enable=1'
	,
		command: 'replace'
		file:
			partition:
				primary: 1
			path: '/cmdline.txt'
		find: 'lpm_enable=1'
		replace: 'lpm_enable=2'
	]

	rindle.wait(configuration).then ->
		imagefs.interact(
			images.raspberrypi
			1
			(_fs) ->
				readFileAsync = Promise.promisify(_fs.readFile)
				return readFileAsync('/cmdline.txt')
					.then (b) -> 
						return b.toString()
		)
	.then (contents) ->
		m.chai.expect(contents).to.equal('dwc_otg.lpm_enable=2 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait \n')

wary.it 'should be able to completely replace a file from an edison partition',
	edison: EDISON
, (images) ->
	configuration = operations.execute images.edison, [
		command: 'replace'
		file:
			path: '/config.json'
		find: /^.*$/g
		replace: 'Replaced!'
	]

	rindle.wait(configuration).then ->
		imagefs.interact(
			images.edison
			undefined
			(_fs) ->
				readFileAsync = Promise.promisify(_fs.readFile)
				return readFileAsync('/config.json')
					.then (b) -> 
						return b.toString()
		)
	.then (contents) ->
		m.chai.expect(contents).to.equal('Replaced!')

wary.it 'should obey when properties',
	raspberrypi: RASPBERRY_PI
, (images) ->
	configuration = operations.execute images.raspberrypi, [
		command: 'replace'
		file:
			partition:
				primary: 1
			path: '/cmdline.txt'
		find: 'lpm_enable=0'
		replace: 'lpm_enable=1'
		when:
			lpm: 1
	,
		command: 'replace'
		file:
			partition:
				primary: 1
			path: '/cmdline.txt'
		find: 'lpm_enable=0'
		replace: 'lpm_enable=2'
		when:
			lpm: 2
	,
		command: 'replace'
		file:
			partition:
				primary: 1
			path: '/cmdline.txt'
		find: 'lpm_enable=0'
		replace: 'lpm_enable=3'
		when:
			lpm: 3
	],
		lpm: 2

	rindle.wait(configuration).then ->
		imagefs.interact(
			images.raspberrypi
			1
			(_fs) ->
				readFileAsync = Promise.promisify(_fs.readFile)
				return readFileAsync('/cmdline.txt')
					.then (b) -> 
						return b.toString()
		)
	.then (contents) ->
		m.chai.expect(contents).to.equal('dwc_otg.lpm_enable=2 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait \n')

wary.it 'should emit state events for operations',
	raspberrypi: RASPBERRY_PI
, (images) ->
	configuration = operations.execute images.raspberrypi, [
		command: 'replace'
		file:
			partition:
				primary: 1
			path: '/cmdline.txt'
		find: 'lpm_enable=0'
		replace: 'lpm_enable=1'
	,
		command: 'replace'
		file:
			partition:
				primary: 1
			path: '/cmdline.txt'
		find: 'lpm_enable=1'
		replace: 'lpm_enable=2'
	,
		command: 'replace'
		file:
			partition:
				primary: 1
			path: '/cmdline.txt'
		find: 'lpm_enable=2'
		replace: 'lpm_enable=1'
	]

	stateSpy = m.sinon.spy()
	configuration.on('state', stateSpy)

	rindle.wait(configuration).then ->
		m.chai.expect(stateSpy.firstCall.args[0]).to.deep.equal
			operation:
				command: 'replace'
				file:
					image: images.raspberrypi
					partition:
						primary: 1
					path: '/cmdline.txt'
				find: 'lpm_enable=0'
				replace: 'lpm_enable=1'
			percentage: 33.3

		m.chai.expect(stateSpy.secondCall.args[0]).to.deep.equal
			operation:
				command: 'replace'
				file:
					image: images.raspberrypi
					partition:
						primary: 1
					path: '/cmdline.txt'
				find: 'lpm_enable=1'
				replace: 'lpm_enable=2'
			percentage: 66.7

		m.chai.expect(stateSpy.thirdCall.args[0]).to.deep.equal
			operation:
				command: 'replace'
				file:
					image: images.raspberrypi
					partition:
						primary: 1
					path: '/cmdline.txt'
				find: 'lpm_enable=2'
				replace: 'lpm_enable=1'
			percentage: 100

wary.it 'should read state events for operations after a slight delay',
	raspberrypi: RASPBERRY_PI
, (images) ->

	configure = ->
		Promise.try ->
			return operations.execute images.raspberrypi, [
				command: 'replace'
				file:
					partition:
						primary: 1
					path: '/cmdline.txt'
				find: 'lpm_enable=0'
				replace: 'lpm_enable=1'
			]

	configure().then (configuration) ->
		stateSpy = m.sinon.spy()
		configuration.on('state', stateSpy)

		rindle.wait(configuration).then ->
			m.chai.expect(stateSpy).to.have.been.calledOnce
			m.chai.expect(stateSpy.firstCall.args[0]).to.deep.equal
				operation:
					command: 'replace'
					file:
						image: images.raspberrypi
						partition:
							primary: 1
						path: '/cmdline.txt'
					find: 'lpm_enable=0'
					replace: 'lpm_enable=1'
				percentage: 100

wary.it 'should run a script with arguments that exits successfully', {}, ->
	configuration = operations.execute EDISON_ZIP, [
		command: 'run-script'
		script: 'echo.cmd'
		arguments: [ 'hello', 'world' ]
	]

	stdout = ''
	stderr = ''

	configuration.on 'stdout', (data) ->
		stdout += data

	configuration.on 'stderr', (data) ->
		stderr += data

	rindle.wait(configuration).then ->
		m.chai.expect(stdout.replace(/\r/g, '')).to.equal('hello world\n')
		m.chai.expect(stderr).to.equal('')

wary.it 'should run a script that prints to stderr', {}, ->
	configuration = operations.execute EDISON_ZIP, [
		command: 'run-script'
		script: 'stderr.cmd'
	]

	stdout = ''
	stderr = ''

	configuration.on 'stdout', (data) ->
		stdout += data

	configuration.on 'stderr', (data) ->
		stderr += data

	rindle.wait(configuration).then ->
		m.chai.expect(stdout).to.equal('')
		m.chai.expect(stderr.replace(/[\r\n]/g, '').trim()).to.equal('stderr output')

wary.it 'should be rejected if the script does not exist', {}, ->
	configuration = operations.execute EDISON_ZIP, [
		command: 'run-script'
		script: 'foobarbaz.cmd'
	]

	promise = rindle.wait(configuration)
	m.chai.expect(promise).to.be.rejectedWith('ENOENT')

wary.it 'should run a script that doesn not have execution privileges', {}, ->
	configuration = operations.execute EDISON_ZIP, [
		command: 'run-script'
		script: 'exec.cmd'
		arguments: [ 'hello', 'world' ]
	]

	stdout = ''
	stderr = ''

	configuration.on 'stdout', (data) ->
		stdout += data

	configuration.on 'stderr', (data) ->
		stderr += data

	rindle.wait(configuration).then ->
		m.chai.expect(stdout.replace(/\r/g, '')).to.equal('hello world\n')
		m.chai.expect(stderr).to.equal('')

wary.it 'should be rejected if the script finishes with an error', {}, ->
	configuration = operations.execute EDISON_ZIP, [
		command: 'run-script'
		script: 'error.cmd'
	]

	promise = rindle.wait(configuration)
	m.chai.expect(promise).to.be.rejectedWith('Exited with error code: 1')

wary.it 'should change directory to the dirname of the script', {}, ->
	configuration = operations.execute EDISON_ZIP, [
		command: 'run-script'
		script: 'cwd.cmd'
	]

	stdout = ''
	stderr = ''

	configuration.on 'stdout', (data) ->
		stdout += data

	configuration.on 'stderr', (data) ->
		stderr += data

	rindle.wait(configuration).then ->
		m.chai.expect(stdout.replace(/\r/g, '')).to.equal("#{EDISON_ZIP}#{path.sep}\n")
		m.chai.expect(stderr).to.equal('')

wary.it 'should be rejected if the burn operation lacks a drive option', {}, ->
	configuration = operations.execute RASPBERRY_PI, [
		command: 'burn'
	]

	promise = rindle.wait(configuration)
	m.chai.expect(promise).to.be.rejectedWith('Missing drive option')

mockBlockDeviceFromFile = (path) ->
	drive = {
		raw: path,
		device: path,
		devicePath: path,
		displayName: path,
		icon: 'some icon',
		isSystem: false,
		description: 'some description',
		mountpoints: [],
		size: fs.statSync(path).size,
		isReadOnly: false,
		busType: 'UNKNOWN',
		error: null,
		blockSize: 512,
		busVersion: null,
		enumerator: 'fake',
		isCard: null,
		isRemovable: true,
		isSCSI: false,
		isUAS: null,
		isUSB: true,
		isVirtual: false,
		logicalBlockSize: 512,
		partitionTableType: null,
	};
	device = new sdk.sourceDestination.BlockDevice({
		drive,
		unmountOnSuccess: false,
		write: true,
		direct: false,
	})

	device._open = () ->
		sdk.sourceDestination.File.prototype._open.call(device)
	device._close = () ->
		sdk.sourceDestination.File.prototype._close.call(device)

	device

wary.it 'should be able to burn an image',
	raspberrypi: RASPBERRY_PI
	random: RANDOM
, (images) ->
	drive = mockBlockDeviceFromFile(images.random)

	configuration = operations.execute images.raspberrypi, [
		command: 'burn'
	], { drive }

	progressSpy = m.sinon.spy()
	configuration.on('burn', progressSpy)

	rindle.wait(configuration).then ->

		fs.statAsync(images.raspberrypi).get('size').then (size) ->
			m.chai.expect(progressSpy).to.have.been.called
			state = progressSpy.firstCall.args[0]
			m.chai.expect(state.length).to.not.equal(0)
			m.chai.expect(state.length).to.equal(size)

	.then ->
		Promise.props
			raspberrypi: fs.readFileAsync(images.raspberrypi)
			random: fs.readFileAsync(images.random)
		.then (results) ->
			m.chai.expect(results.random).to.deep.equal(results.raspberrypi)

wary.it 'should set an os option automatically',
	edison: EDISON
, (images) ->
	configuration = operations.execute images.edison, [
			command: 'replace'
			file:
				path: '/config.json'
			find: /^.*$/g
			replace: 'win32'
			when:
				os: 'win32'
		,
			command: 'replace'
			file:
				path: '/config.json'
			find: /^.*$/g
			replace: 'osx'
			when:
				os: 'osx'
		,
			command: 'replace'
			file:
				path: '/config.json'
			find: /^.*$/g
			replace: 'linux'
			when:
				os: 'linux'
	]

	rindle.wait(configuration).then ->
		imagefs.interact(
			images.edison
			undefined
			(_fs) ->
				readFileAsync = Promise.promisify(_fs.readFile)
				return readFileAsync('/config.json')
					.then (b) -> 
						return b.toString()
		)
	.then (contents) ->
		m.chai.expect(contents).to.equal(utils.getOperatingSystem())

wary.it 'should allow the os option to be overrided',
	edison: EDISON
, (images) ->
	configuration = operations.execute images.edison, [
			command: 'replace'
			file:
				path: '/config.json'
			find: /^.*$/g
			replace: 'win32'
			when:
				os: 'win32'
		,
			command: 'replace'
			file:
				path: '/config.json'
			find: /^.*$/g
			replace: 'osx'
			when:
				os: 'osx'
		,
			command: 'replace'
			file:
				path: '/config.json'
			find: /^.*$/g
			replace: 'linux'
			when:
				os: 'linux'
		,
			command: 'replace'
			file:
				path: '/config.json'
			find: /^.*$/g
			replace: 'resinos'
			when:
				os: 'resinos'
	],
		os: 'resinos'

	rindle.wait(configuration).then ->
		imagefs.interact(
			images.edison
			undefined
			(_fs) ->
				readFileAsync = Promise.promisify(_fs.readFile)
				return readFileAsync('/config.json')
					.then (b) -> 
						return b.toString()
		)
	.then (contents) ->
		m.chai.expect(contents).to.equal('resinos')

wary.run().catch (error) ->
	console.error(error.message)
	process.exit(1)
