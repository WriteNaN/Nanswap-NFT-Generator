# NaNFT Generator
![image](https://github.com/WriteNaN/Nanswap-NFT-Generator/assets/151211283/735b782d-147c-4cf1-9101-f5a853dddd98)

> Generate NFTs from layers ready to use in https://nanswap.art/

## Prerequisites
1. [ImageMagick](https://imagemagick.org/script/download.php)

## Usage
### Install from releases[¹](https://github.com/WriteNaN/Nanswap-NFT-Generator/releases):
This program is only tested on Linux, although maybe compatible with other os I highly recommend you to use WSL or something similar.

* Copy the path of installed command
#### Quick command example:
```js
./<generator> -i examples/input.json -o dist -n 100
```
> this command outputs nanswap.art publishable directory where input is a valid json file (please refer examples/input.json here), dist is the folder where your output files go to and -n is the number of nfts you want to generate, optionally you can use --zip argument to zip it. the folder will be deleted once done. progress can be seen while being generated.

#### Building from source:
(You should have Zig installed)
* Installation
```shell
git clone https://github.com/WriteNaN/Nanswap-NFT-Generator gen
```
* Build
```shell
zig build -Doptimize=ReleaseFast
```
optionally you can add -Dtarget[²](https://ziglang.org/learn/build-system/) here.
