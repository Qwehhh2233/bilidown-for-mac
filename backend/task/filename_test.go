package task

import (
	"testing"
)

func TestLegacyFilename(t *testing.T) {
	task := TaskInDB{
		TaskInitOption: TaskInitOption{
			Title:        "示例视频",
			DownloadType: "merge",
		},
		ID: 42,
	}

	got := task.legacyFileName()
	want := "示例视频 NDI.mp4"
	if got != want {
		t.Fatalf("legacyFileName() = %q, want %q", got, want)
	}

	task.DownloadType = "audio"
	if got := task.legacyFileName(); got != "示例视频 NDI.m4a" {
		t.Fatalf("audio legacyFileName() = %q, want %q", got, "示例视频 NDI.m4a")
	}
}
