from setuptools import setup, find_packages

setup(
    name='entking',
    packages=find_packages(),
    entry_points={
        'console_scripts': [
            'entking=entking.app:serve',
        ],
    },
)
