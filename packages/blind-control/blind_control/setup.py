from setuptools import setup, find_packages

setup(
    name='blind_control',
    py_modules=['blind_control'],
    entry_points={
        'console_scripts': [
            'blind_control=blind_control:main',
        ],
    },
)
