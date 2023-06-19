
using l.misc;

public class DownloadTask : AsyncTask {

	// settings
	public int timeout_secs = 60;

	// item lists
	Gee.ArrayList<DownloadItem> downloads;
	Gee.HashMap<string, DownloadItem> map;
	Gee.HashMap<string,Regex> regex = null;

	public DownloadTask() {

		base();

		downloads = new Gee.ArrayList<DownloadItem>();
		map = new Gee.HashMap<string, DownloadItem>();
		regex = new Gee.HashMap<string,Regex>();

		try {
			//[#4df0c7 19283968B/45095814B(42%) CN:1 DL:105404B ETA:4m4s]
			regex["file-progress"] = new Regex("""^\[#([^ \t]+)[ \t]+([0-9]+)B\/([0-9]+)B\(([0-9]+)%\)[ \t]+[^ \t]+[ \t]+DL\:([0-9]+)B[ \t]+ETA\:([^ \]]+)\]""");

			//12/03 21:15:33 [NOTICE] Download complete: /home/teejee/.cache/ukuu/v4.7.8/CHANGES
			regex["file-complete"] = new Regex("""[0-9A-Z\/: ]*\[NOTICE\] Download complete\: (.*)""");

			//8ae3a3|OK  |    16KiB/s|/home/teejee/.cache/ukuu/v4.0.7-wily/index.html
			//bea740|OK  |        n/a|/home/teejee/.cache/ukuu/v4.0.9-wily/CHANGES
			regex["file-status"] = new Regex("""^([0-9A-Za-z]+)\|(OK|ERR)[ ]*\|[ ]*(n\/a|[0-9.]+[A-Za-z\/]+)\|(.*)""");
		}
		catch (Error e) {
			vprint(e.message,1,stderr);
		}
	}

	// execution ----------------------------

	public void add_to_queue(DownloadItem item) {
		item.task = this;
		downloads.add(item);
		// https://aria2.github.io/manual/en/html/aria2c.html#cmdoption-gid
		// Only the first 6 chars of gid are shown in the progress output, and they
		// are shown in lower case even if they were supplied in upper case.
		// So gid must be lower-case and the first 6 characters must be unique.
		do { item.gid = "%8.8x%8.8x".printf(Main.rnd.next_int(),Main.rnd.next_int()); }
		while (map.has_key(item.gid_key));
		map[item.gid_key] = item;
	}

	public void execute() {
		prepare();
		begin();
	}

	public void prepare() {
		vprint("prepare():",2);
		stdin_data = "";

		foreach (var item in downloads) {
			stdin_data += item.source_uri + "\n"
				+ " gid="+item.gid+"\n"
				+ " dir="+item.download_dir+"\n"
				+ " out="+item.file_name+"\n"
				;
			if (item.checksum.length>0) stdin_data += ""
				+ " checksum="+item.checksum+"\n"
				+ " check-integrity=true\n"
				;
		}

		string[] cmd = {
			"aria2c",
			//"--max-download-limit=256K",  // force slow download for debugging
			"--input-file=-",
			"--no-netrc=true",
			"--no-conf=true",
			"--summary-interval=1",
			"--auto-save-interval=1",
			"--enable-color=false",
			"--allow-overwrite",
			"--timeout=600",
			"--max-file-not-found=3",
			"--retry-wait=2",
			"--show-console-readout=false",
			"--download-result=full",
			"--human-readable=false"
		};

		if (App.connect_timeout_seconds>0) cmd += "--connect-timeout="+App.connect_timeout_seconds.to_string();

		if (App.concurrent_downloads>0) {
			cmd += "--max-concurrent-downloads="+App.concurrent_downloads.to_string();
			cmd += "--max-connection-per-server="+App.concurrent_downloads.to_string();
		}

		if (App.all_proxy.length>0) cmd += "--all-proxy='"+App.all_proxy+"'";

		spawn_args = cmd;
	}

	public override void parse_stdout_line(string line) {
		if ((line == null) || (line.length == 0)) return;

		//vprint(line,2);

		MatchInfo match;

		if (regex["file-complete"].match(line, 0, out match)) {
			//vprint("match: file-complete: " + line,2);
			prg_count++;
		} else if (regex["file-status"].match(line, 0, out match)) {

			//8ae3a3|OK  |    16KiB/s|/home/teejee/.cache/ukuu/v4.0.7-wily/index.html

			string gid_key = match.fetch(1).strip();
			string status = match.fetch(2).strip();
			//int64 rate = int64.parse(match.fetch(3).strip());
			//string file = match.fetch(4).strip();

			if (map.has_key(gid_key)) {
				var item = map[gid_key];
				item.status = status;
				//if (status=="OK") {
				//	item.bytes_received = item.bytes_total;
				//	status_line = item.file_name+" "+item.bytes_received.to_string()+"/"+item.bytes_total.to_string();
				//}
			}

		} else if (regex["file-progress"].match(line, 0, out match)) {

			var gid_key = match.fetch(1).strip();
			var received = int64.parse(match.fetch(2).strip());
			var total = int64.parse(match.fetch(3).strip());
			//var percent = double.parse(match.fetch(4).strip());
			//var rate = int64.parse(match.fetch(5).strip());
			//var eta = match.fetch(6).strip();

			if (map.has_key(gid_key)) {
				var item = map[gid_key];
				item.bytes_received = received;
				if (item.bytes_total == 0) item.bytes_total = total;
				status_line = item.file_name+" "+received.to_string()+"/"+total.to_string();
			}
		}

		return;
	}
}

public class DownloadItem : GLib.Object {
	// File is saved as 'file_name' in 'download_dir', not the source file name.

	public string source_uri = "";		// "https://kernel.ubuntu.com/~kernel-ppa/mainline/v6.2.7/amd64/linux-headers-6.2.7-060207-generic_6.2.7-060207.202303170542_amd64.deb"
	public string download_dir = "";	// "/home/bkw/.cache/mainline/6.2.7/amd64"
	public string file_name = "";		// "linux-headers-6.2.7-060207-generic_6.2.7-060207.202303170542_amd64.deb"
	public string checksum = "";		// "sha-256=4a90d708984d6a8fab68411710be09aa2614fe1be5b5e054a872b155d15faab6"

	public string gid = ""; // ID
	public int64 bytes_total = 0;
	public int64 bytes_received = 0;
	public string status = "";

	public DownloadTask task = null;

	// only the first 6 chars of gid are shown in the progress output
	public string gid_key {
		owned get {
			return gid.substring(0,6);
		}
	}

	public DownloadItem(string uri = "", string destdir = "", string fname = "", string? cksum = "") {
		if (cksum==null) cksum = "";
		vprint("DownloadItem("+uri+","+destdir+","+fname+","+cksum+")",3);
		source_uri = uri;
		file_name = fname;
		download_dir = destdir;
		checksum = cksum;
	}
}
