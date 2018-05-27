#!/usr/bin/env python
# -*- coding: utf-8 -*-
from os.path import dirname, join
from setuptools import setup

setup(
    name='als-yoga',
    version='0.0.1',
    description='Ambient light sensor yoga',
    license='GPL',
    py_modules=['als'],
    entry_points={
        'console_scripts': [
            'als-yoga=als:main',
        ],
    },
)
