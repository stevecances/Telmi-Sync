import { appendFileSync, readFileSync } from 'fs'
import { execFileSync } from 'child_process'
import { isNewerVersion } from '../public/MainEvents/Helpers/Version.js'

const
  api = `https://api.github.com/repos/${process.env.GITHUB_REPOSITORY}`,
  headers = {
    Accept: 'application/vnd.github+json',
    ...(process.env.GITHUB_TOKEN ? { Authorization: `Bearer ${process.env.GITHUB_TOKEN}` } : {})
  },
  setOutput = (name, value) => appendFileSync(process.env.GITHUB_OUTPUT, `${name}=${value}\n`),
  skip = (reason) => {
    console.log(`::warning::Release ignorée : ${reason}`)
    setOutput('new', 'false')
  },
  tagExists = (tag) => execFileSync('git', ['ls-remote', '--tags', 'origin', `refs/tags/${tag}`]).toString().trim() !== '',
  listReleases = async () => {
    const res = await fetch(`${api}/releases?per_page=100`, { headers })
    if (!res.ok) {
      throw new Error(`GitHub API releases : ${res.status}`)
    }
    return res.json()
  }

const main = async () => {
  const { version } = JSON.parse(readFileSync('package.json', 'utf8'))
  setOutput('version', version)

  if (!/^\d+\.\d+\.\d+$/.test(version)) {
    return skip(`format de version invalide (${version})`)
  }
  if (tagExists(version)) {
    return skip(`le tag ${version} existe déjà`)
  }

  const releases = await listReleases()
  if (releases.some((release) => release.tag_name === version)) {
    return skip(`une release (brouillon compris) ${version} existe déjà`)
  }

  const latest = releases.find((release) => !release.draft && !release.prerelease)
  if (latest && !isNewerVersion(latest.tag_name, version)) {
    return skip(`${version} n'est pas supérieure à ${latest.tag_name}`)
  }

  setOutput('new', 'true')
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
