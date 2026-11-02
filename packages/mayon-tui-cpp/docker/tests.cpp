// Ports the Rust tests of packages/mayon-tui/crates/docker/src/{api,cleanup,vm,vm_xml,app,lib}.rs.
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <filesystem>
#include <format>
#include <fstream>
#include <ftxui/screen/screen.hpp>
#include <set>
#include <string>
#include <vector>

#include "api.hpp"
#include "app.hpp"
#include "cli.hpp"
#include "cleanup.hpp"
#include "page.hpp"
#include "ui/draw.hpp"
#include "ui/search.hpp"
#include "ui/text.hpp"
#include "vm.hpp"
#include "vm_xml.hpp"

extern char** environ;

using namespace dock;
using tui::Key;
using tui::KeyCode;

namespace {
json load(const char* text) { return json::parse(text); }
Disk disk_of(const json& value) { return decode_disk(value); }
tui::Key ch(char32_t code) { return Key{KeyCode::Char, code}; }
tui::Key code(KeyCode value) { return Key{value}; }
std::string text_of(ftxui::Screen& screen) { return screen.ToString(); }
void press(App& app, const Key& key) {
    tui::InputEvent event;
    event.type = tui::InputEvent::Type::Key;
    event.key = key;
    app.handle(event);
}
std::vector<std::string> words(const std::string& text) {
    std::vector<std::string> out;
    size_t at = 0;
    while (at < text.size()) {
        while (at < text.size() && text[at] == ' ') ++at;
        const size_t end = text.find(' ', at);
        if (end == std::string::npos) {
            if (at < text.size()) out.push_back(text.substr(at));
            break;
        }
        out.push_back(text.substr(at, end - at));
        at = end + 1;
    }
    return out;
}
cleanup::Entry entry(cleanup::Kind kind, const std::string& id, std::optional<uint64_t> reclaim) {
    cleanup::Entry out;
    out.kind = kind;
    out.id = id;
    out.name = id;
    out.size = reclaim;
    out.reclaim = reclaim;
    return out;
}
struct Fixture {
    std::filesystem::path path;
    Fixture() {
        static int next = 0;
        path = std::filesystem::temp_directory_path() / std::format("mayon-docker-tests-{}-{}", ::getpid(), next++);
        std::filesystem::create_directories(path);
    }
    ~Fixture() {
        std::error_code error;
        std::filesystem::remove_all(path, error);
    }
    std::filesystem::path file(const std::string& name, uint64_t size) const {
        const auto target = path / name;
        std::filesystem::create_directories(target.parent_path());
        std::ofstream stream(target, std::ios::binary);
        stream.seekp(static_cast<std::streamoff>(size) - 1);
        stream.put('\0');
        stream.close();
        return target;
    }
};
vm::Connection connection(const std::string& uri, bool complete) { return vm::Connection{uri, "fixture", complete}; }
vm::Row vm_row(const std::string& uri, const std::string& kind, std::optional<std::string> path, std::optional<uint64_t> actual) {
    vm::Row row;
    row.uri = uri;
    row.owner = "fixture";
    row.kind = kind;
    row.path = std::move(path);
    row.actual = actual;
    return row;
}
}  // namespace

TEST_CASE("compose and stats decode") {
    const Container container = decode_container(load(R"({"Id":"abc","Names":["/web"],"Image":"nginx","State":"running","Status":"Up 2 minutes","Labels":{"com.docker.compose.project":"demo"},"Ports":[{"IP":"0.0.0.0","PrivatePort":80,"PublicPort":8080,"Type":"tcp"}]})"));
    CHECK(container.labels.at("com.docker.compose.project") == "demo");
    REQUIRE(container.ports.size() == 1);
    CHECK(container.ports[0].public_port == 8080);
    const StatView view = decode_stats(load(R"({"cpu_stats":{"cpu_usage":{"total_usage":30},"system_cpu_usage":200,"online_cpus":2},"precpu_stats":{"cpu_usage":{"total_usage":10},"system_cpu_usage":100,"online_cpus":2},"memory_stats":{"usage":1000,"limit":5000,"stats":{"inactive_file":200}}})"));
    CHECK(view.cpu == doctest::Approx(40.0).epsilon(0.01));
    CHECK(view.memory == 800);
}

TEST_CASE("null and empty collections are accepted and df supplies volume usage") {
    const Disk disk = disk_of(load(R"({"Images":null,"Containers":null,"Volumes":[{"Name":"data","UsageData":{"Size":1234,"RefCount":2}}],"BuildCache":null})"));
    CHECK(disk.images.empty());
    CHECK(disk.containers.empty());
    CHECK(disk.build_cache.empty());
    std::vector<Volume> volumes = decode_volumes(load(R"({"Volumes":[{"Name":"data","UsageData":null},{"Name":"unknown"}]})"));
    merge_volume_usage(volumes, disk);
    REQUIRE(volumes[0].usage.has_value());
    CHECK(volumes[0].usage->size == 1234);
    CHECK(!volumes[1].usage.has_value());
    const Image image = decode_image(load(R"({"Id":"i","RepoTags":null,"Size":1})"));
    CHECK(image.tags.empty());
}

TEST_CASE("decoders reject wrong JSON types instead of guessing") {
    CHECK_THROWS_AS(decode_container(load(R"({"Id":12})")), std::runtime_error);
    CHECK_THROWS_AS(decode_image(load(R"({"Id":"i","Size":"big"})")), std::runtime_error);
    CHECK_THROWS_AS(decode_disk(load(R"({"Images":{}})")), std::runtime_error);
    CHECK_THROWS_AS(decode_volumes(load(R"({"Volumes":{}})")), std::runtime_error);
    CHECK_THROWS_AS(decode_stats(load(R"({"cpu_stats":{},"precpu_stats":{},"memory_stats":{"stats":{"x":-1}}})")), std::runtime_error);
}

TEST_CASE("multiplex logs") {
    std::string buffer;
    buffer.push_back(1);
    buffer.append(3, '\0');
    buffer.append(std::string("\0\0\0\4", 4));
    buffer += "hey\n";
    buffer.push_back(2);
    buffer.append(3, '\0');
    buffer.append(std::string("\0\0\0\3", 4));
    buffer += "err";
    std::string partial = buffer.substr(0, 11);
    CHECK(drain_log_frames(partial).empty());
    partial += buffer.substr(11);
    CHECK(drain_log_frames(partial) == std::vector<std::string>{"hey", "err"});
    CHECK(partial.empty());
    std::string raw = "line one\r\npart";
    CHECK(drain_raw_log_lines(raw) == std::vector<std::string>{"line one"});
    raw += "ial\n";
    CHECK(drain_raw_log_lines(raw) == std::vector<std::string>{"partial"});
    CHECK(raw.empty());
}

TEST_CASE("url encoded ids and hazard gates") {
    CHECK(enc("vol/a") == "vol%2Fa");
    CHECK_THROWS_AS(cache_prune_path("abc.*"), std::runtime_error);
    CHECK(cache_prune_path("abc").find("%5Eabc%24") != std::string::npos);
    CHECK(is_default_docker_socket("unix:///run/user/1000/docker.sock", "/run/user/1000"));
    CHECK(!is_default_docker_socket("unix:///tmp/docker-test.sock", "/run/user/1000"));
}

TEST_CASE("dangling tags and log buffer caps") {
    CHECK(is_dangling({}));
    CHECK(is_dangling({"<none>:<none>"}));
    CHECK(!is_dangling({"nginx:1"}));
    std::string buffer(8, 'x');
    CHECK(!cap_log_buffer(buffer, 8));
    buffer.push_back('x');
    CHECK(cap_log_buffer(buffer, 8));
    CHECK(buffer.empty());
}

TEST_CASE("running paused restarting unknown and missing states are locked") {
    const Disk disk = disk_of(load(R"({"Containers":[
        {"Id":"running","State":"running","SizeRw":10},
        {"Id":"paused","State":"paused","SizeRw":20},
        {"Id":"restarting","State":"restarting","SizeRw":30},
        {"Id":"unknown","State":"removing","SizeRw":40},
        {"Id":"missing","SizeRw":50},
        {"Id":"stopped","State":"exited","SizeRw":60}]})"));
    std::vector<std::pair<std::string, bool>> rows;
    for (const cleanup::Entry& row : cleanup::entries(disk)) {
        if (row.kind == cleanup::Kind::Container) rows.emplace_back(row.id, row.selectable());
    }
    CHECK(rows == std::vector<std::pair<std::string, bool>>{
        {"stopped", true}, {"missing", false}, {"unknown", false}, {"restarting", false}, {"paused", false}, {"running", false}});
}

TEST_CASE("image and volume reference lists override zero refcounts") {
    const Disk disk = disk_of(load(R"({
        "Images":[
            {"Id":"sha256:used","Containers":0,"Size":100,"SharedSize":0,"RepoTags":["used:1"]},
            {"Id":"sha256:free","Containers":0,"Size":80,"SharedSize":0,"RepoTags":["free:1"]}],
        "Containers":[{"Id":"stopped","ImageID":"sha256:used","State":"exited","SizeRw":1,
                       "Mounts":[{"Type":"volume","Name":"mounted-zero-ref"}]}],
        "Volumes":[
            {"Name":"mounted-zero-ref","UsageData":{"Size":50,"RefCount":0}},
            {"Name":"truly-free","UsageData":{"Size":40,"RefCount":0}}]})"));
    const auto rows = cleanup::entries(disk);
    const auto find = [&](const std::string& id) {
        return std::find_if(rows.begin(), rows.end(), [&](const cleanup::Entry& row) { return row.id == id; });
    };
    CHECK(!find("sha256:used")->selectable());
    CHECK(find("sha256:free")->selectable());
    CHECK(!find("mounted-zero-ref")->selectable());
    CHECK(find("truly-free")->selectable());
}

TEST_CASE("unknown reference data fails closed and no rows are selected by default") {
    const Disk disk = disk_of(load(R"({
        "Images":[
            {"Id":"sha256:unknown-count","Size":10,"RepoTags":["unknown:1"]},
            {"Id":"sha256:unknown-shared","Containers":0,"Size":20,"SharedSize":-1,"RepoTags":["unknown-shared:1"]}],
        "Volumes":[
            {"Name":"unknown-refs","UsageData":{"Size":100}},
            {"Name":"unknown-size","UsageData":{"RefCount":0}}]})"));
    const auto rows = cleanup::entries(disk);
    const auto find = [&](const std::string& id) {
        return std::find_if(rows.begin(), rows.end(), [&](const cleanup::Entry& row) { return row.id == id; });
    };
    CHECK(!find("sha256:unknown-count")->selectable());
    CHECK(find("sha256:unknown-shared")->selectable());
    CHECK(!find("unknown-refs")->selectable());
    CHECK(find("unknown-size")->selectable());
    CHECK(!find("sha256:unknown-shared")->reclaim.has_value());
    CHECK(!find("unknown-size")->size.has_value());
    CHECK(cleanup::selected(rows, {}).empty());
}

TEST_CASE("reclaim subtracts shared image layers saturates and sorts by size") {
    const Disk disk = disk_of(load(R"({
        "Images":[
            {"Id":"small","Containers":0,"Size":30,"SharedSize":10,"RepoTags":["small:1"]},
            {"Id":"large","Containers":0,"Size":100,"SharedSize":20,"RepoTags":["large:1"]},
            {"Id":"overshared","Containers":0,"Size":5,"SharedSize":99,"RepoTags":["overshared:1"]}],
        "BuildCache":[
            {"ID":"cache-own","Size":40,"InUse":false,"Shared":false},
            {"ID":"cache-shared","Size":90,"InUse":false,"Shared":true}]})"));
    const auto rows = cleanup::entries(disk);
    const auto find = [&](const std::string& id) {
        return std::find_if(rows.begin(), rows.end(), [&](const cleanup::Entry& row) { return row.id == id; });
    };
    CHECK(find("large")->reclaim == 80);
    CHECK(find("overshared")->reclaim == 0);
    CHECK(find("cache-shared")->reclaim == 0);
    for (size_t i = 1; i < rows.size(); ++i) CHECK(rows[i - 1].size >= rows[i].size);
    CHECK(cleanup::estimate({entry(cleanup::Kind::Cache, "a", UINT64_MAX), entry(cleanup::Kind::Image, "b", 9)}) ==
          cleanup::bytes(UINT64_MAX));
    CHECK(cleanup::sum_sizes({UINT64_MAX, 1}).first == UINT64_MAX);
}

TEST_CASE("plan preview must reach each item before two confirmations") {
    const std::vector<cleanup::Entry> plan{entry(cleanup::Kind::Image, "image-id-full", 10),
                                           entry(cleanup::Kind::Container, "container-id-full", 20)};
    auto flow = cleanup::Flow::create(plan);
    REQUIRE(flow.has_value());
    CHECK(flow->stage == cleanup::Stage::Preview);
    CHECK(!flow->handle_key(ch(U'y')).has_value());
    CHECK(flow->stage == cleanup::Stage::Preview);
    CHECK(!flow->handle_key(code(KeyCode::Down)).has_value());
    CHECK(flow->cursor == 1);
    CHECK(flow->body().find("container-id-full") != std::string::npos);
    CHECK(!flow->handle_key(ch(U'y')).has_value());
    CHECK(flow->stage == cleanup::Stage::Confirm);
    CHECK(flow->handle_key(ch(U'y')) == plan);
}

TEST_CASE("volume plan needs second confirmation and full delete phrase") {
    const std::vector<cleanup::Entry> plan{entry(cleanup::Kind::Volume, "named-volume", 512)};
    auto flow = cleanup::Flow::create(plan);
    REQUIRE(flow.has_value());
    CHECK(flow->body().find("卷数据不可恢复") != std::string::npos);
    CHECK(!flow->handle_key(ch(U'y')).has_value());
    CHECK(flow->stage == cleanup::Stage::Confirm);
    CHECK(!flow->handle_key(ch(U'y')).has_value());
    CHECK(flow->stage == cleanup::Stage::Volumes);
    CHECK(flow->volume_phrase() == "DELETE named-volume");
    for (const char c : std::string("DELETE named-volumeX")) CHECK(!flow->handle_key(ch(static_cast<unsigned char>(c))).has_value());
    CHECK(!flow->handle_key(code(KeyCode::Enter)).has_value());
    CHECK(!flow->handle_key(code(KeyCode::Backspace)).has_value());
    CHECK(flow->handle_key(code(KeyCode::Enter)) == plan);
}

TEST_CASE("every volume requires its own full name") {
    const std::vector<cleanup::Entry> plan{entry(cleanup::Kind::Volume, "first", 10),
                                           entry(cleanup::Kind::Volume, "second", 20)};
    auto flow = cleanup::Flow::create(plan);
    REQUIRE(flow.has_value());
    flow->handle_key(code(KeyCode::Down));
    flow->handle_key(ch(U'y'));
    flow->handle_key(ch(U'y'));
    for (const char c : std::string("DELETE first")) flow->handle_key(ch(static_cast<unsigned char>(c)));
    CHECK(!flow->handle_key(code(KeyCode::Enter)).has_value());
    CHECK(flow->volume_phrase() == "DELETE second");
    CHECK(flow->input.empty());
    CHECK(!flow->handle_key(code(KeyCode::Enter)).has_value());
    for (const char c : std::string("DELETE second")) flow->handle_key(ch(static_cast<unsigned char>(c)));
    CHECK(flow->handle_key(code(KeyCode::Enter)) == plan);
}

TEST_CASE("long display names cannot hide the full preview id") {
    cleanup::Entry item = entry(cleanup::Kind::Image, "sha256:review-this-exact-id", 1);
    item.name = "huge-tag";
    for (int i = 0; i < 1000; ++i) item.name += "huge-tag";
    auto flow = cleanup::Flow::create({item});
    REQUIRE(flow.has_value());
    const std::string body = flow->body();
    CHECK(body.find("sha256:review-this-exact-id") < 100);
    CHECK(body.size() < 1000);
}

TEST_CASE("CLI parsing mirrors the Rust safety rules") {
    CliArgs args;
    std::string error;
    CHECK(!parse_cli_args(words("clean --yes"), args, error));
    CHECK(!parse_cli_args(words("df --yes"), args, error));
    CHECK(!parse_cli_args(words("df --volume data"), args, error));
    CHECK(!parse_cli_args(words("--yes"), args, error));
    CHECK(!parse_cli_args(words("clean --image abc --volume"), args, error));
    CHECK(!parse_cli_args(words("clean"), args, error));
    CHECK(!parse_cli_args(words("--host"), args, error));
    CliArgs parsed;
    REQUIRE(parse_cli_args(words("clean --image abc"), parsed, error));
    CHECK(!parsed.yes);
    parsed = CliArgs{};
    REQUIRE(parse_cli_args(words("clean --yes --image abc --image abc"), parsed, error));
    CHECK(parsed.targets.size() == 1);
    parsed = CliArgs{};
    REQUIRE(parse_cli_args(words("clean --yes --volume data"), parsed, error));
    REQUIRE(parsed.targets.size() == 1);
    CHECK(parsed.targets[0].first == cleanup::Kind::Volume);
    CHECK(parsed.targets[0].second == "data");
    parsed = CliArgs{};
    REQUIRE(parse_cli_args(words("--host unix:///tmp/x"), parsed, error));
    CHECK(parsed.host == "unix:///tmp/x");
    CHECK(!parsed.command.has_value());
    CHECK(!parse_cli_args(words("unknown"), parsed, error));
    CHECK(docker_cli(1, nullptr) == -1);
}

TEST_CASE("plan_for rejects locked or unknown selections") {
    const Disk disk = disk_of(load(R"({"Images":[{"Id":"free","Containers":0,"Size":1,"RepoTags":["f:1"]}],
        "Containers":[{"Id":"running","State":"running","SizeRw":1}]})"));
    const auto rows = cleanup::entries(disk);
    CHECK_THROWS_AS(plan_for(rows, {{cleanup::Kind::Container, "running"}}), std::runtime_error);
    CHECK_THROWS_AS(plan_for(rows, {{cleanup::Kind::Image, "missing"}}), std::runtime_error);
    CHECK(plan_for(rows, {{cleanup::Kind::Image, "free"}}).size() == 1);
}

TEST_CASE("libvirt XML parser decodes chains and entities") {
    const auto parsed = xml::parse(R"(<?xml version="1.0"?>
        <!-- metadata only -->
        <domain><name>guest &amp; lab</name><devices>
          <disk type='file' device='disk'><source file='/vms/磁盘 &quot;A&quot;.qcow2'/>
            <backingStore><format type='qcow2'/><source file='/pool/base&amp;seed.qcow2'/>
              <backingStore><source file='/pool/root.qcow2'/></backingStore>
            </backingStore>
          </disk>
        </devices></domain>)");
    REQUIRE(parsed.has_value());
    REQUIRE(parsed->child("name") != nullptr);
    CHECK(parsed->child("name")->text == "guest & lab");
    const auto disks = parsed->descendants("disk");
    REQUIRE(disks.size() == 1);
    REQUIRE(disks[0]->attr("type") != nullptr);
    CHECK(*disks[0]->attr("type") == "file");
    const auto sources = disks[0]->descendants("source");
    REQUIRE(sources.size() == 3);
    CHECK(*sources[0]->attr("file") == "/vms/磁盘 \"A\".qcow2");
    CHECK(*sources[1]->attr("file") == "/pool/base&seed.qcow2");
    CHECK(*sources[2]->attr("file") == "/pool/root.qcow2");
}

TEST_CASE("libvirt XML parses numeric entities and self closing elements") {
    const auto root = xml::parse("<pool><path>/x&#32;&#x2F;é</path><volume/></pool>");
    REQUIRE(root.has_value());
    CHECK(root->child("path")->text == "/x /é");
    CHECK(root->child("volume")->children.empty());
}

TEST_CASE("libvirt XML rejects entities declarations and malformed documents") {
    for (const char* text : {"<!DOCTYPE x [<!ENTITY e SYSTEM 'file:///etc/passwd'>]><x>&e;</x>",
                             "<x>&external;</x>", "<x>&#0;</x>", "<x><y></x>", "<x>", "<x/><y/>",
                             "<x a=unquoted/>", "<x a='1' a='2'/>"}) {
        CHECK_MESSAGE(!xml::parse(text).has_value(), text);
    }
}

TEST_CASE("libvirt XML enforces size and nesting limits") {
    const std::string huge = "<x>" + std::string(xml::kMaxInput, ' ') + "</x>";
    const auto too_big = xml::parse(huge);
    REQUIRE(!too_big.has_value());
    CHECK(too_big.error().find("4 MiB") != std::string::npos);
    std::string deep;
    for (size_t i = 0; i < xml::kMaxDepth; ++i) deep += "<x>";
    deep += "x";
    for (size_t i = 0; i < xml::kMaxDepth; ++i) deep += "</x>";
    CHECK(xml::parse(deep).has_value());
    const auto too_deep = xml::parse("<x>" + deep + "</x>");
    REQUIRE(!too_deep.has_value());
    CHECK(too_deep.error().find("64") != std::string::npos);
}

TEST_CASE("metadata row reports sparse allocation separately from virtual size") {
    Fixture fixture;
    const uint64_t logical = 64 * 1024 * 1024;
    const auto path = fixture.file("sparse disk.qcow2", logical);
    struct stat info {};
    REQUIRE(::stat(path.c_str(), &info) == 0);
    const vm::Row disk = vm::metadata_row("qemu:///session", "guest", "磁盘", path.string(), logical, "fixture");
    CHECK(disk.actual == static_cast<uint64_t>(info.st_blocks) * 512);
    CHECK(disk.virtual_size == logical);
    CHECK(disk.actual != disk.virtual_size);
}

TEST_CASE("volume paths preserves spaces and rejects unknown block paths") {
    const auto rows = vm::volume_paths("Name                 Path\n----------------------------------------\nbase disk.qcow2       /pool with spaces/基础镜像.qcow2\n");
    REQUIRE(rows.has_value());
    CHECK(*rows == std::vector<std::string>{"/pool with spaces/基础镜像.qcow2"});
    CHECK(!vm::volume_paths("Name Path\n----------------\nvolume0 unknownblockpath\n").has_value());
}

TEST_CASE("merge protects cross connection refs and hardlinks and dedupes the summary") {
    Fixture fixture;
    const auto base = fixture.file("base.qcow2", 32 * 1024 * 1024);
    const auto hardlink = fixture.path / "orphan-looking.qcow2";
    std::filesystem::create_hard_link(base, hardlink);
    const std::string real_base = vm::canonical(base.string());
    const std::string real_link = vm::canonical(hardlink.string());
    struct stat info {};
    REQUIRE(::stat(real_base.c_str(), &info) == 0);
    const uint64_t expected_actual = static_cast<uint64_t>(info.st_blocks) * 512;
    vm::Census session;
    session.refs.insert(real_base);
    session.rows.push_back(vm::metadata_row("qemu:///session", "guest", "依赖", real_base, std::nullopt, "backingStore"));
    vm::Census system;
    system.volumes.push_back(vm::metadata_row("qemu:///system", "pool", "扫描文件", real_base, std::nullopt, "pool file"));
    system.volumes.push_back(vm::metadata_row("qemu:///system", "pool", "扫描文件", real_link, std::nullopt, "hardlink alias"));
    const vm::Inventory inventory = vm::merge({{session, connection("qemu:///session", true)},
                                               {system, connection("qemu:///system", true)}});
    for (const std::string& path : {real_base, real_link}) {
        const auto found = std::find_if(inventory.rows.begin(), inventory.rows.end(), [&](const vm::Row& row) {
            return row.uri == "qemu:///system" && row.path == std::optional<std::string>(path);
        });
        REQUIRE(found != inventory.rows.end());
        CHECK(found->kind == "依赖");
    }
    const std::string summary = inventory.summary();
    CHECK(summary.find(cleanup::bytes(expected_actual)) != std::string::npos);
    CHECK(summary.find(cleanup::bytes(0)) != std::string::npos);
}

TEST_CASE("incomplete connections turn unreferenced images into pending review") {
    Fixture fixture;
    const std::string image = vm::canonical(fixture.file("candidate.qcow2", 4096).string());
    vm::Census census;
    census.volumes.push_back(vm::metadata_row("qemu:///session", "pool", "扫描文件", image, std::nullopt, "candidate"));
    const vm::Inventory inventory = vm::merge({{census, connection("qemu:///session", false)}});
    const auto found = std::find_if(inventory.rows.begin(), inventory.rows.end(), [&](const vm::Row& row) {
        return row.path == std::optional<std::string>(image);
    });
    REQUIRE(found != inventory.rows.end());
    CHECK(found->kind == "未引用待核实");
}

TEST_CASE("snapshot references protect volume candidates") {
    Fixture fixture;
    const std::string snapshot = vm::canonical(fixture.file("snapshot.qcow2", 8192).string());
    vm::Census census;
    census.refs.insert(snapshot);
    census.rows.push_back(vm::metadata_row("qemu:///system", "guest / snapshot", "快照磁盘", snapshot, std::nullopt, "snapshot reference"));
    census.volumes.push_back(vm::metadata_row("qemu:///system", "pool", "扫描文件", snapshot, std::nullopt, "pool alias"));
    const vm::Inventory inventory = vm::merge({{census, connection("qemu:///system", true)}});
    const auto found = std::find_if(inventory.rows.begin(), inventory.rows.end(), [&](const vm::Row& row) {
        return row.uri == "qemu:///system" && row.path == std::optional<std::string>(snapshot);
    });
    REQUIRE(found != inventory.rows.end());
    CHECK(found->kind == "快照磁盘");
    CHECK(found->note.find("snapshot reference") != std::string::npos);
}

TEST_CASE("merge sorts known sizes descending then unknown") {
    vm::Census census;
    census.volumes.push_back(vm_row("qemu:///session", "小", "/z", 10));
    census.volumes.push_back(vm_row("qemu:///session", "大", "/a", 20));
    census.rows.push_back(vm_row("qemu:///session", "未知", std::nullopt, std::nullopt));
    const vm::Inventory inventory = vm::merge({{census, connection("qemu:///session", true)}});
    REQUIRE(inventory.rows.size() >= 3);
    CHECK(inventory.rows[0].actual == 20);
    CHECK(inventory.rows[0].path == std::optional<std::string>("/a"));
    CHECK(inventory.rows[1].actual == 10);
    CHECK(inventory.rows[1].path == std::optional<std::string>("/z"));
    CHECK(!inventory.rows[2].actual.has_value());
    CHECK(!inventory.rows[2].path.has_value());
}

TEST_CASE("vm rows never enter the docker cleanup selection") {
    const vm::Row vm = vm_row("qemu:///system", "镜像", "/vm/disk.qcow2", 10);
    const std::vector<cleanup::Entry> docker{entry(cleanup::Kind::Cache, "cache-id", 20)};
    const std::set<std::string> keys{vm.key(), docker[0].key()};
    CHECK(cleanup::selected(docker, keys) == docker);
}

TEST_CASE("domain disks collect backing datastore and mirror references") {
    Fixture fixture;
    const std::string top = (fixture.path / "top.qcow2").string();
    const std::string base = (fixture.path / "base.qcow2").string();
    const std::string data = (fixture.path / "data.qcow2").string();
    const std::string mirror_source = (fixture.path / "mirror-source.qcow2").string();
    const std::string legacy_mirror = (fixture.path / "legacy-mirror.qcow2").string();
    const std::string xml_text = std::format(R"(<domain><devices><disk type="file" device="disk">
        <driver type="qcow2"/><source file="{}"/>
        <backingStore type="file"><format type="qcow2"/><source file="{}"/><backingStore/></backingStore>
        <dataStore><source file="{}"/></dataStore>
        <mirror file="{}"><source file="{}"/></mirror>
        </disk></devices></domain>)", top, base, data, legacy_mirror, mirror_source);
    const auto root = xml::parse(xml_text);
    REQUIRE(root.has_value());
    vm::Census census;
    const vm::Budget budget{nullptr, std::chrono::steady_clock::now() + std::chrono::seconds(30)};
    vm::domain_disks(census, budget, "qemu:///session", "fixture", *root, false);
    for (const std::string& path : {top, base, data, mirror_source, legacy_mirror}) CHECK(census.refs.contains(path));
    CHECK(census.warnings.empty());
}

TEST_CASE("domain disks mark an unterminated backing chain incomplete") {
    Fixture fixture;
    const std::string top = (fixture.path / "unterminated-top.qcow2").string();
    const std::string base = (fixture.path / "unterminated-base.qcow2").string();
    const std::string xml_text = std::format(R"(<domain><devices><disk type="file" device="disk">
        <driver type="qcow2"/><source file="{}"/>
        <backingStore type="file"><source file="{}"/></backingStore>
        </disk></devices></domain>)", top, base);
    const auto root = xml::parse(xml_text);
    REQUIRE(root.has_value());
    vm::Census census;
    const vm::Budget budget{nullptr, std::chrono::steady_clock::now() + std::chrono::seconds(30)};
    vm::domain_disks(census, budget, "qemu:///system", "fixture", *root, false);
    CHECK(census.refs.contains(top));
    CHECK(census.refs.contains(base));
    const bool warned = std::any_of(census.warnings.begin(), census.warnings.end(), [](const std::string& warning) {
        return warning.find("backing 链未明确终止") != std::string::npos;
    });
    CHECK(warned);
}

TEST_CASE("raw disk without a backing chain is complete") {
    Fixture fixture;
    const std::string raw = (fixture.path / "raw-without-chain.img").string();
    const std::string xml_text = std::format(R"(<domain><devices><disk type="file" device="disk">
        <driver type="raw"/><source file="{}"/>
        </disk></devices></domain>)", raw);
    const auto root = xml::parse(xml_text);
    REQUIRE(root.has_value());
    vm::Census census;
    const vm::Budget budget{nullptr, std::chrono::steady_clock::now() + std::chrono::seconds(30)};
    vm::domain_disks(census, budget, "qemu:///session", "fixture", *root, false);
    CHECK(census.refs.contains(raw));
    CHECK(census.warnings.empty());
}

TEST_CASE("cross connection ISO aliases stay ISO and do not inflate virtual capacity") {
    Fixture fixture;
    const auto path = fixture.file("installer.iso", 1024);
    const std::string real = vm::canonical(path.string());
    vm::Census session;
    session.refs.insert(real);
    session.rows.push_back(vm::metadata_row(vm::kUris[0], "vm", "ISO", real, 1024, "mounted"));
    vm::Census system;
    system.volumes.push_back(vm::metadata_row(vm::kUris[1], "pool", "扫描文件", real, 1024, "file"));
    const vm::Inventory report = vm::merge({{session, connection(vm::kUris[0], true)},
                                            {system, connection(vm::kUris[1], true)}});
    for (const vm::Row& row : report.rows) {
        if (row.path) CHECK(row.kind == "ISO");
    }
    CHECK(report.summary().find("已知虚拟 0.0 B") != std::string::npos);
}

TEST_CASE("filtering images is incremental and keeps stable ids") {
    App app(std::optional<std::string>("unix:///tmp/docker-tui-test.sock"));
    app.page = PageId::Images;
    app.online = true;
    app.images.push_back(decode_image(load(R"({"Id":"a","RepoTags":["北京 Apple"]})")));
    app.images.push_back(decode_image(load(R"({"Id":"b","RepoTags":["香港 Apple"]})")));
    app.selected = 1;
    press(app, ch(U'/'));
    app.paste_text("apple");
    CHECK(app.selected_id() == std::optional<std::string>("b"));
    press(app, code(KeyCode::Up));
    CHECK(app.selected_id() == std::optional<std::string>("a"));
    app.paste_text(" nonexistent");
    CHECK(app.len() == 0);
    CHECK(app.selected == 0);
    ftxui::Screen screen(100, 30);
    app.draw(screen, tui::Rect{0, 0, 100, 30});
    CHECK(text_of(screen).find("无匹配项") != std::string::npos);
    press(app, code(KeyCode::Escape));
    CHECK(app.len() == 2);
    press(app, ch(U'/'));
    app.paste_text("xianggang apple");
    CHECK(app.selected_id() == std::optional<std::string>("b"));
    press(app, code(KeyCode::Enter));
    press(app, ch(U'/'));
    app.paste_text(" xyz");
    press(app, code(KeyCode::Escape));
    CHECK(app.filter.str() == "xianggang apple");
    press(app, code(KeyCode::Escape));
    CHECK(app.len() == 2);
}

TEST_CASE("filtered log refresh preserves the scrolled record even at the buffer limit") {
    App app(std::optional<std::string>("unix:///tmp/docker-tui-test.sock"));
    app.log_filter.set("keep");
    for (int i = 0; i < 4000; ++i) app.log_lines.push_back(std::format("keep {}", i));
    app.log_follow = false;
    app.log_scroll = 20;
    const auto anchor = [&] {
        std::vector<std::string> rows;
        for (const std::string& line : app.log_lines) {
            if (tui::match(app.log_filter.str(), line)) rows.push_back(line);
        }
        return rows[rows.size() - app.log_scroll - 1];
    };
    const std::string before = anchor();
    app.last_refresh = std::chrono::steady_clock::now();
    app.apply_log(app.api_epoch, "skip\nkeep 4000");
    CHECK(anchor() == before);
    CHECK(app.log_lines.size() == 4000);
    CHECK(app.log_scroll == 21);
}

TEST_CASE("suspend keeps the log view state and cancels background jobs") {
    App app(std::optional<std::string>("unix:///tmp/docker-tui-test.sock"));
    app.filter.set("容器");
    app.log_filter.set("apple");
    app.logs = "fixture";
    app.log_lines = {"Apple retained"};
    app.log_scroll = 1;
    app.refresh_running = true;
    app.log_running = true;
    app.set_active(false);
    CHECK(!app.has_api_job());
    app.set_active(true);
    CHECK(app.filter.str() == "容器");
    CHECK(app.log_filter.str() == "apple");
    CHECK(app.log_lines == std::vector<std::string>{"Apple retained"});
    CHECK(app.log_scroll == 1);
    CHECK(app.log_running);
    app.set_active(false);
}

TEST_CASE("vm jobs only exist while the vm inventory is visible") {
    App app(std::optional<std::string>("unix:///tmp/docker-tui-test.sock"));
    app.set_active(true);
    app.last_refresh = std::chrono::steady_clock::now();
    app.tick();
    CHECK(!app.vm_running);
    app.page = PageId::Cleanup;
    app.vm_section = true;
    app.vm_running = true;
    press(app, code(KeyCode::Tab));
    CHECK(!app.vm_running);
    app.vm_section = true;
    app.vm_running = true;
    press(app, ch(U'1'));
    CHECK(!app.vm_running);
    app.set_active(false);
}

TEST_CASE("log capture has a byte budget even for large lines") {
    App app(std::optional<std::string>("unix:///tmp/docker-tui-test.sock"));
    app.log_lines.clear();
    app.apply_log(app.api_epoch, std::string(5 * 1024 * 1024, 'x'));
    size_t total = 0;
    for (const std::string& line : app.log_lines) total += line.size();
    CHECK(total <= 4 * 1024 * 1024);
}

TEST_CASE("vm section never enters docker cleanup or selects resources") {
    App app(std::optional<std::string>("unix:///tmp/docker-tui-test.sock"));
    app.page = PageId::Cleanup;
    app.vm_section = true;
    app.picked.insert("镜像:fixture");
    press(app, ch(U' '));
    press(app, ch(U'd'));
    press(app, code(KeyCode::Enter));
    CHECK(!app.cleanup_flow.has_value());
    CHECK(!app.confirm.has_value());
    CHECK(!app.action_running);
    CHECK(app.picked.size() == 1);
    CHECK(app.message.find("严格只读") != std::string::npos);
    press(app, code(KeyCode::Tab));
    CHECK(!app.vm_section);
}

TEST_CASE("vm navigation and refresh work while docker is suspended") {
    App app(std::optional<std::string>("unix:///tmp/docker-tui-test.sock"));
    app.page = PageId::Cleanup;
    app.stopped_by_user = true;
    press(app, code(KeyCode::Tab));
    CHECK(app.vm_section);
    press(app, ch(U'r'));
    CHECK(std::chrono::steady_clock::now() - app.last_vm >= std::chrono::seconds(30));
    press(app, code(KeyCode::Enter));
    CHECK(!app.refresh_running);
    CHECK(!app.action_running);
    CHECK(app.stopped_by_user);
}

TEST_CASE("suspended docker does not resume through retained cleanup selection") {
    App app(std::optional<std::string>("unix:///tmp/docker-tui-test.sock"));
    app.page = PageId::Cleanup;
    app.stopped_by_user = true;
    app.picked.insert("镜像:fixture");
    app.disk.images.push_back(ImageDisk{"fixture", 0, 32, 0, {}});
    press(app, code(KeyCode::Enter));
    press(app, ch(U'y'));
    press(app, ch(U'y'));
    CHECK(!app.cleanup_flow.has_value());
    CHECK(!app.action_running);
    CHECK(!app.refresh_running);
    CHECK(app.stopped_by_user);
}

TEST_CASE("stopped daemon rejects a real action key") {
    App app(std::optional<std::string>("unix:///tmp/docker-tui-test.sock"));
    app.stopped_by_user = true;
    press(app, ch(U'r'));
    CHECK(!app.action_running);
    CHECK(app.message.find("按 s") != std::string::npos);
}

TEST_CASE("refresh snapshot does not replace a recent action message") {
    App app(std::optional<std::string>("unix:///tmp/docker-tui-test.sock"));
    app.message = "构建缓存清理完成 · 实际释放 192 MiB";
    app.message_until = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    app.last_refresh = std::chrono::steady_clock::now();
    Data data;
    data.info.version = "test";
    app.apply_data(app.api_epoch, std::move(data));
    CHECK(app.message == "构建缓存清理完成 · 实际释放 192 MiB");
}

TEST_CASE("container details preserve full image status and bind ip") {
    const Container container = decode_container(load(R"({"Id":"abc123","Names":["/api"],"Image":"python:3.12-alpine","State":"running","Status":"Up 18 minutes","Ports":[{"IP":"0.0.0.0","PrivatePort":8000,"PublicPort":8080,"Type":"tcp"}]})"));
    const std::string details = container_details(container);
    CHECK(details.find("python:3.12-alpine") != std::string::npos);
    CHECK(details.find("Up 18 minutes (running)") != std::string::npos);
    CHECK(details.find("0.0.0.0:8080 → :8000/tcp") != std::string::npos);
    CHECK(tui::width_of(compact_port_mappings(container)) <= 15);
}

TEST_CASE("enter opens details and details block mouse until escape") {
    App app(std::optional<std::string>("unix:///tmp/docker-tui-test.sock"));
    app.containers.push_back(decode_container(load(R"({"Id":"abc123","Names":["/api"]})")));
    app.set_active(true);
    press(app, code(KeyCode::Enter));
    CHECK(app.details);
    ftxui::Screen screen(90, 30);
    app.draw(screen, tui::Rect{0, 0, 90, 30});
    tui::InputEvent click;
    click.type = tui::InputEvent::Type::MouseClick;
    click.x = 14;
    click.y = 1;
    app.handle(click);
    CHECK(app.page == PageId::Containers);
    press(app, code(KeyCode::Escape));
    CHECK(!app.details);
    app.set_active(false);
}

TEST_CASE("stop allows navigation but blocks daemon requests") {
    for (const char32_t c : std::u32string(U"q?1sjk/o")) CHECK(stopped_key_allowed(ch(c)));
    CHECK(stopped_key_allowed(code(KeyCode::Escape)));
    CHECK(stopped_key_allowed(code(KeyCode::Down)));
    for (const char32_t c : std::u32string(U"rpledcbS")) CHECK(!stopped_key_allowed(ch(c)));
}

TEST_CASE("tabs follow rendered unicode cell widths") {
    const std::vector<std::string> names{"容器", "镜像", "卷", "概览", "空间"};
    CHECK(tui::tab_at(2, 1, names) == 0);
    CHECK(tui::tab_at(10, 1, names) == 1);
    CHECK(tui::tab_at(18, 1, names) == 2);
    CHECK(tui::tab_at(26, 1, names) == 3);
    CHECK(tui::tab_at(34, 1, names) == 4);
}

TEST_CASE("table click uses the scroll offset for long lists") {
    CHECK(table_click_index(0, 10, 7, 30) == 7);
    CHECK(table_click_index(19, 10, 4, 30) == 14);
    CHECK(table_click_index(29, 10, 9, 30) == 29);
}

TEST_CASE("compose restart targets every container in only that project") {
    Container a = decode_container(load(R"({"Id":"a"})"));
    a.labels["com.docker.compose.project"] = "alpha";
    Container b = decode_container(load(R"({"Id":"b"})"));
    b.labels["com.docker.compose.project"] = "alpha";
    Container c = decode_container(load(R"({"Id":"c"})"));
    c.labels["com.docker.compose.project"] = "beta";
    CHECK(compose_project_ids({a, b, c}, "alpha") == std::vector<std::string>{"a", "b"});
}

TEST_CASE("stale api updates stay discarded after reconnect") {
    CHECK(!api_update_is_current(4, 5, false));
    CHECK(!api_update_is_current(5, 5, true));
    CHECK(api_update_is_current(5, 5, false));
}

TEST_CASE("compact status shortens docker durations") {
    CHECK(compact_status("Up 2 minutes") == "Up 2m");
    CHECK(compact_status("Exited (0) 2 hours ago") == "Exit (0) 2h");
}

TEST_CASE("cleanup step preview and volume phrase never authorize early") {
    const std::vector<cleanup::Entry> plan{entry(cleanup::Kind::Image, "img", 1),
                                           entry(cleanup::Kind::Volume, "vol", 2)};
    auto flow = cleanup::Flow::create(plan);
    REQUIRE(flow.has_value());
    CHECK(!flow->handle_key(ch(U'y')).has_value());
    flow->handle_key(code(KeyCode::Down));
    flow->handle_key(ch(U'y'));
    flow->handle_key(ch(U'y'));
    CHECK(flow->stage == cleanup::Stage::Volumes);
    CHECK(flow->volume_phrase() == "DELETE vol");
    CHECK(!flow->handle_key(code(KeyCode::Enter)).has_value());
}

#ifdef PYTHON
namespace {
int run_mock(const std::string& script) {
    const std::string python = PYTHON;
    const std::string demo = DEMO;
    std::vector<std::string> args{python, "-B", script, demo};
    std::vector<char*> argv;
    for (std::string& arg : args) argv.push_back(arg.data());
    argv.push_back(nullptr);
    pid_t pid = -1;
    if (posix_spawnp(&pid, python.c_str(), nullptr, nullptr, argv.data(), environ) != 0) return -1;
    int status = 0;
    while (::waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) return -1;
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}
}  // namespace

TEST_CASE("docker CLI end to end against the mock engine") {
    CHECK(run_mock(std::string(FIXTURES) + "/cli_mock.py") == 0);
}

TEST_CASE("docker df VM end to end against mock virsh") {
    CHECK(run_mock(std::string(FIXTURES) + "/vm_mock.py") == 0);
}
#endif

TEST_CASE("remote text is stripped of control characters but keeps docker tags") {
    CHECK(safe(std::string("a\x1b[31mb")) == "a[31mb");
    CHECK(safe("<none>:<none>") == "<none>:<none>");
    CHECK(safe("line\nnext\x07") == "line\nnext");
    CHECK(split_lines("a\r\nb\n") == std::vector<std::string>{"a", "b"});
}

TEST_CASE("engine refuses non-unix endpoints and the page reports the unavailable state") {
    CHECK_THROWS_WITH(Engine::create(std::optional<std::string>("tcp://127.0.0.1:2375")),
                      doctest::Contains("仅支持 unix://"));
    App app(std::optional<std::string>("tcp://127.0.0.1:2375"));
    CHECK(!app.engine.has_value());
    CHECK(!app.init_error.empty());
    CHECK(!app.has_api_job());
    ftxui::Screen screen(100, 30);
    app.draw(screen, tui::Rect{0, 0, 100, 30});
    CHECK(text_of(screen).find("仅支持 unix://") != std::string::npos);
    press(app, ch(U'q'));
    CHECK(app.quit);
}

TEST_CASE("a docker page does not connect before it is first activated") {
    App app(std::optional<std::string>("unix:///tmp/docker-tui-test.sock"));
    CHECK(app.engine.has_value());
    CHECK(!app.has_api_job());
    app.page = PageId::Cleanup;
    app.vm_section = true;
    app.tick();  // inactive: must not start the refresh or the vm inventory
    CHECK(!app.has_api_job());
}

TEST_CASE("editing covers filters cleanup previews and confirmations") {
    App app(std::optional<std::string>("unix:///tmp/docker-tui-test.sock"));
    CHECK(!app.editing());
    press(app, ch(U'/'));
    CHECK(app.editing());
    press(app, code(KeyCode::Escape));
    CHECK(!app.editing());
    app.page = PageId::Cleanup;
    app.disk.images.push_back(ImageDisk{"sha256:free", 0, 16, 0, {"free:1"}});
    app.picked.insert("镜像:sha256:free");
    press(app, code(KeyCode::Enter));
    REQUIRE(app.cleanup_flow.has_value());
    CHECK(app.editing());
    press(app, code(KeyCode::Escape));
    CHECK(!app.editing());
    Container container = decode_container(load(R"({"Id":"abc","Names":["/web"],"Labels":{"com.docker.compose.project":"demo"}})"));
    app.containers.push_back(std::move(container));
    app.page = PageId::Containers;
    press(app, ch(U'R'));
    REQUIRE(app.confirm.has_value());
    CHECK(app.editing());
    press(app, code(KeyCode::Escape));
    CHECK(!app.editing());
}
