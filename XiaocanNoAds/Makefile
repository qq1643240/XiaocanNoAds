THEOS_PACKAGE_NAME = com.xiaocan.noads
ARCHS = arm64
TARGET = iphone:clang:latest:15.0

# variant 由 THEOS_PACKAGE_SCHEME 控制: rootless (默认) / roothide / 留空=rootful
# 推荐用 scripts/build.sh，会自动准备 control 文件并设置 scheme。
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = XiaocanNoAds
XiaocanNoAds_FILES = Tweak.xm \
                     XCNoAdsConfig.m \
                     XCPrefsController.m
XiaocanNoAds_FRAMEWORKS = UIKit Foundation
XiaocanNoAds_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable

include $(THEOS_MAKE_PATH)/tweak.mk

.PHONY: clean
clean::
	rm -rf $(THEOS_BUILD_DIR) packages
