from subprocess import check_output

FSWEBCAM_ARGS = [
    'fswebcam',
    '--palette', 'UYVY',
    '--resolution', '640x480',
    '-d', '/dev/video1',
    '--png',
    '--save',
]

def capture_image(capture_file):
    check_output([*FSWEBCAM_ARGS, capture_file])

